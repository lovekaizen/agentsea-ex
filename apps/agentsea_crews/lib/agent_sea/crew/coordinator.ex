defmodule AgentSea.Crew.Coordinator do
  @moduledoc """
  Drives a crew's task DAG, modeled as a `:gen_statem` whose states *are* the
  crew lifecycle: `:idle → :running → :completed`, with `:paused` (pause/resume)
  and `:aborted` branches.

  On `kickoff/1` it dispatches every task whose dependencies are satisfied to an
  agent (chosen by the delegation strategy) as a supervised `Task`. Results
  arrive as messages; dependents unlock as their dependencies complete; tasks
  whose dependencies failed are marked `:dependency_failed`. When everything is
  settled it replies to the kickoff caller with the aggregate result.

  `pause` stops dispatching new tasks (in-flight work finishes), `resume`
  continues, and `abort` cancels in-flight tasks and settles the crew. Invalid
  transitions return `{:error, {:invalid_status, state}}`.
  """

  @behaviour :gen_statem

  alias AgentSea.Crew
  alias AgentSea.Crew.{Delegation, Supervisor}
  alias AgentSea.Crew.Task, as: CrewTask

  # --- Client API (target a crew by name; gen_statem speaks the gen_server call
  # protocol, so GenServer.call works) ---

  def start_link(%Crew.Spec{name: name} = spec) do
    :gen_statem.start_link(Supervisor.via(name, :coordinator), __MODULE__, spec, [])
  end

  def child_spec(spec) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [spec]}}
  end

  def add_task(crew, attrs), do: GenServer.call(via(crew), {:add_task, attrs})
  def kickoff(crew, timeout \\ 60_000), do: GenServer.call(via(crew), :kickoff, timeout)
  def status(crew), do: GenServer.call(via(crew), :status)

  @doc "Stop dispatching new tasks; in-flight tasks finish. Only valid while `:running`."
  def pause(crew), do: GenServer.call(via(crew), :pause)

  @doc "Resume dispatching after a pause. Only valid while `:paused`."
  def resume(crew), do: GenServer.call(via(crew), :resume)

  @doc "Cancel in-flight tasks and settle as `:aborted`; the kickoff caller gets `{:error, :aborted}`."
  def abort(crew), do: GenServer.call(via(crew), :abort)

  defp via(crew), do: Supervisor.via(crew, :coordinator)

  # --- gen_statem setup ---

  @impl :gen_statem
  def callback_mode, do: :handle_event_function

  @impl :gen_statem
  def init(%Crew.Spec{} = spec) do
    data = %{
      spec: spec,
      agents: [],
      tasks: %{},
      results: %{},
      failures: %{},
      # Elixir Task ref -> crew task id, for in-flight work
      running: %{},
      rr_counter: 0,
      caller: nil,
      kickoff_started: nil
    }

    {:ok, :idle, data, [{:next_event, :internal, :start_agents}]}
  end

  # --- Events ---

  @impl :gen_statem
  def handle_event(:internal, :start_agents, :idle, data) do
    agent_sup = Supervisor.via(data.spec.name, :agent_sup)

    agents =
      Enum.map(data.spec.agents, fn config ->
        {:ok, pid} = DynamicSupervisor.start_child(agent_sup, {AgentSea.Agent, config})
        %{name: config.name, pid: pid, role: config.role}
      end)

    {:keep_state, %{data | agents: agents}}
  end

  # add_task: only while idle.
  def handle_event({:call, from}, {:add_task, attrs}, :idle, data) do
    task = CrewTask.new(attrs)

    {:keep_state, %{data | tasks: Map.put(data.tasks, task.id, task)},
     [{:reply, from, {:ok, task}}]}
  end

  def handle_event({:call, from}, {:add_task, _attrs}, state, _data) do
    {:keep_state_and_data, [{:reply, from, {:error, {:invalid_status, state}}}]}
  end

  # kickoff: only from idle.
  def handle_event({:call, from}, :kickoff, :idle, data) do
    :telemetry.execute(
      [:agentsea, :crew, :kickoff, :start],
      %{system_time: System.system_time()},
      %{crew: data.spec.name, task_count: map_size(data.tasks)}
    )

    data = dispatch_ready(%{data | caller: from, kickoff_started: System.monotonic_time()})

    if settled?(data), do: finish_completed(data), else: {:next_state, :running, data}
  end

  def handle_event({:call, from}, :kickoff, state, _data) do
    {:keep_state_and_data, [{:reply, from, {:error, {:invalid_status, state}}}]}
  end

  # status: the gen_statem state name is the status.
  def handle_event({:call, from}, :status, state, _data) do
    {:keep_state_and_data, [{:reply, from, state}]}
  end

  # pause: only while running.
  def handle_event({:call, from}, :pause, :running, data) do
    {:next_state, :paused, data, [{:reply, from, :ok}]}
  end

  def handle_event({:call, from}, :pause, state, _data) do
    {:keep_state_and_data, [{:reply, from, {:error, {:invalid_status, state}}}]}
  end

  # resume: only while paused.
  def handle_event({:call, from}, :resume, :paused, data) do
    data = dispatch_ready(data)

    if settled?(data) do
      {data, actions} = finish(data)
      {:next_state, :completed, data, [{:reply, from, :ok} | actions]}
    else
      {:next_state, :running, data, [{:reply, from, :ok}]}
    end
  end

  def handle_event({:call, from}, :resume, state, _data) do
    {:keep_state_and_data, [{:reply, from, {:error, {:invalid_status, state}}}]}
  end

  # abort: while running or paused.
  def handle_event({:call, from}, :abort, state, data) when state in [:running, :paused] do
    task_sup = Supervisor.via(data.spec.name, :task_sup)

    for pid <- Task.Supervisor.children(task_sup) do
      Task.Supervisor.terminate_child(task_sup, pid)
    end

    for ref <- Map.keys(data.running), do: Process.demonitor(ref, [:flush])

    emit_kickoff_stop(data, false)
    caller_actions = if data.caller, do: [{:reply, data.caller, {:error, :aborted}}], else: []

    {:next_state, :aborted, %{data | running: %{}, caller: nil},
     [{:reply, from, :ok} | caller_actions]}
  end

  def handle_event({:call, from}, :abort, state, _data) do
    {:keep_state_and_data, [{:reply, from, {:error, {:invalid_status, state}}}]}
  end

  # A delegated task finished (Agent.run returned {:ok, _} | {:error, _}).
  def handle_event(:info, {ref, {:task_done, task_id, result}}, state, data)
      when state in [:running, :paused] do
    if is_map_key(data.running, ref) do
      Process.demonitor(ref, [:flush])
      progress(state, record_done(data, ref, task_id, result))
    else
      :keep_state_and_data
    end
  end

  # A delegated Task process crashed before replying.
  def handle_event(:info, {:DOWN, ref, :process, _pid, reason}, state, data)
      when state in [:running, :paused] do
    if is_map_key(data.running, ref) do
      {task_id, running} = Map.pop(data.running, ref)
      emit_task_stop(data, task_id, :crashed)

      data = %{
        data
        | failures: Map.put(data.failures, task_id, {:crashed, reason}),
          running: running
      }

      progress(state, data)
    else
      :keep_state_and_data
    end
  end

  # Ignore everything else (stray messages in settled states, etc.).
  def handle_event(_type, _content, _state, _data), do: :keep_state_and_data

  # --- Advancing the DAG ---

  # Running: record + try to dispatch more, then maybe complete. Paused: record
  # only (no new dispatch); complete only if everything happens to be settled.
  defp progress(:running, data) do
    data = dispatch_ready(data)
    if settled?(data), do: finish_completed(data), else: {:keep_state, data}
  end

  defp progress(:paused, data) do
    if settled?(data), do: finish_completed(data), else: {:keep_state, data}
  end

  defp finish_completed(data) do
    {data, actions} = finish(data)
    {:next_state, :completed, data, actions}
  end

  defp finish(data) do
    result = %{
      success: map_size(data.failures) == 0,
      results: data.results,
      failures: data.failures
    }

    emit_kickoff_stop(data, result.success)
    actions = if data.caller, do: [{:reply, data.caller, {:ok, result}}], else: []
    {%{data | caller: nil}, actions}
  end

  defp record_done(data, ref, task_id, result) do
    data = %{data | running: Map.delete(data.running, ref)}

    case result do
      {:ok, response} ->
        emit_task_stop(data, task_id, :ok)
        %{data | results: Map.put(data.results, task_id, response)}

      {:error, reason} ->
        emit_task_stop(data, task_id, :error)
        %{data | failures: Map.put(data.failures, task_id, reason)}
    end
  end

  defp dispatch_ready(data) do
    pending =
      for {id, task} <- data.tasks,
          not done?(data, id),
          not running?(data, id),
          do: task

    Enum.reduce(pending, data, fn task, acc ->
      cond do
        blocked?(acc, task) -> put_failure(acc, task.id, :dependency_failed)
        deps_ready?(acc, task) -> dispatch_one(acc, task)
        true -> acc
      end
    end)
  end

  defp dispatch_one(data, task) do
    ctx = Map.put(data.spec.delegation_ctx, :counter, data.rr_counter)

    case Delegation.select(data.spec.strategy, task, data.agents, ctx) do
      {:ok, %Delegation.Result{selected_agent: name}} ->
        agent = Enum.find(data.agents, &(&1.name == name))
        task_sup = Supervisor.via(data.spec.name, :task_sup)

        :telemetry.execute(
          [:agentsea, :crew, :task, :start],
          %{system_time: System.system_time()},
          %{crew: data.spec.name, task_id: task.id, agent: name}
        )

        t =
          Task.Supervisor.async_nolink(task_sup, fn ->
            {:task_done, task.id, AgentSea.Agent.run(agent.pid, CrewTask.input(task))}
          end)

        %{data | running: Map.put(data.running, t.ref, task.id), rr_counter: data.rr_counter + 1}

      {:error, reason} ->
        put_failure(data, task.id, {:delegation_failed, reason})
    end
  end

  # --- Predicates / helpers ---

  defp settled?(data) do
    map_size(data.running) == 0 and
      Enum.all?(data.tasks, fn {id, _task} -> done?(data, id) end)
  end

  defp done?(data, id),
    do: Map.has_key?(data.results, id) or Map.has_key?(data.failures, id)

  defp running?(data, id), do: id in Map.values(data.running)

  defp deps_ready?(data, %CrewTask{depends_on: deps}),
    do: Enum.all?(deps, &Map.has_key?(data.results, &1))

  defp blocked?(data, %CrewTask{depends_on: deps}) do
    Enum.any?(deps, fn dep ->
      Map.has_key?(data.failures, dep) or not Map.has_key?(data.tasks, dep)
    end)
  end

  defp put_failure(data, id, reason),
    do: %{data | failures: Map.put(data.failures, id, reason)}

  defp emit_task_stop(data, task_id, outcome) do
    :telemetry.execute(
      [:agentsea, :crew, :task, :stop],
      %{system_time: System.system_time()},
      %{crew: data.spec.name, task_id: task_id, outcome: outcome}
    )
  end

  defp emit_kickoff_stop(data, success) do
    duration =
      if data.kickoff_started, do: System.monotonic_time() - data.kickoff_started, else: 0

    :telemetry.execute(
      [:agentsea, :crew, :kickoff, :stop],
      %{duration: duration},
      %{crew: data.spec.name, success: success, task_count: map_size(data.tasks)}
    )
  end
end
