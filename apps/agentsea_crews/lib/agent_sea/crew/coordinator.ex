defmodule AgentSea.Crew.Coordinator do
  @moduledoc """
  Drives a crew's task DAG.

  On `kickoff/1` it dispatches every task whose dependencies are satisfied to an
  agent (chosen by the delegation strategy) as a supervised `Task`. Results
  arrive as messages; dependents unlock as their dependencies complete; tasks
  whose dependencies failed are marked `:dependency_failed`. When everything is
  settled it replies to the kickoff caller with the aggregate result.

  Lifecycle status: `:idle → :running → :completed`, with `pause/1`, `resume/1`,
  and `abort/1` controls — `pause` stops dispatching new tasks (in-flight work
  finishes), `resume` continues from where it left off, and `abort` cancels
  in-flight tasks and settles the crew (`:running ⇄ :paused`, either `→ :aborted`).
  """

  use GenServer

  alias AgentSea.Crew
  alias AgentSea.Crew.{Delegation, Supervisor}
  alias AgentSea.Crew.Task, as: CrewTask

  # --- Client API (target a crew by name) ---

  def start_link(%Crew.Spec{name: name} = spec) do
    GenServer.start_link(__MODULE__, spec, name: Supervisor.via(name, :coordinator))
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

  # --- Server ---

  @impl true
  def init(%Crew.Spec{} = spec) do
    state = %{
      spec: spec,
      status: :idle,
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

    {:ok, state, {:continue, :start_agents}}
  end

  @impl true
  def handle_continue(:start_agents, %{spec: spec} = state) do
    agent_sup = Supervisor.via(spec.name, :agent_sup)

    agents =
      Enum.map(spec.agents, fn config ->
        {:ok, pid} = DynamicSupervisor.start_child(agent_sup, {AgentSea.Agent, config})
        %{name: config.name, pid: pid, role: config.role}
      end)

    {:noreply, %{state | agents: agents}}
  end

  @impl true
  def handle_call({:add_task, attrs}, _from, %{status: :idle} = state) do
    task = CrewTask.new(attrs)
    {:reply, {:ok, task}, %{state | tasks: Map.put(state.tasks, task.id, task)}}
  end

  def handle_call({:add_task, _attrs}, _from, state) do
    {:reply, {:error, {:invalid_status, state.status}}, state}
  end

  def handle_call(:kickoff, from, %{status: :idle} = state) do
    :telemetry.execute(
      [:agentsea, :crew, :kickoff, :start],
      %{system_time: System.system_time()},
      %{crew: state.spec.name, task_count: map_size(state.tasks)}
    )

    state =
      %{state | status: :running, caller: from, kickoff_started: System.monotonic_time()}
      |> dispatch_ready()

    if settled?(state) do
      complete(state)
    else
      {:noreply, state}
    end
  end

  def handle_call(:kickoff, _from, state) do
    {:reply, {:error, {:invalid_status, state.status}}, state}
  end

  def handle_call(:status, _from, state), do: {:reply, state.status, state}

  def handle_call(:pause, _from, %{status: :running} = state) do
    {:reply, :ok, %{state | status: :paused}}
  end

  def handle_call(:pause, _from, state) do
    {:reply, {:error, {:invalid_status, state.status}}, state}
  end

  def handle_call(:resume, _from, %{status: :paused} = state) do
    state = dispatch_ready(%{state | status: :running})

    if settled?(state) do
      {:noreply, completed} = complete(state)
      {:reply, :ok, completed}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call(:resume, _from, state) do
    {:reply, {:error, {:invalid_status, state.status}}, state}
  end

  def handle_call(:abort, _from, %{status: status} = state) when status in [:running, :paused] do
    task_sup = Supervisor.via(state.spec.name, :task_sup)

    for pid <- Task.Supervisor.children(task_sup) do
      Task.Supervisor.terminate_child(task_sup, pid)
    end

    # Drop the monitors (and any queued DOWNs) for the tasks we just killed.
    for ref <- Map.keys(state.running), do: Process.demonitor(ref, [:flush])

    emit_kickoff_stop(state, false)
    if state.caller, do: GenServer.reply(state.caller, {:error, :aborted})

    {:reply, :ok, %{state | status: :aborted, running: %{}, caller: nil}}
  end

  def handle_call(:abort, _from, state) do
    {:reply, {:error, {:invalid_status, state.status}}, state}
  end

  # A delegated task finished (Agent.run returned {:ok, _} | {:error, _}).
  @impl true
  def handle_info({ref, {:task_done, task_id, result}}, %{running: running} = state)
      when is_map_key(running, ref) do
    Process.demonitor(ref, [:flush])

    state =
      case result do
        {:ok, response} ->
          emit_task_stop(state, task_id, :ok)
          %{state | results: Map.put(state.results, task_id, response)}

        {:error, reason} ->
          emit_task_stop(state, task_id, :error)
          %{state | failures: Map.put(state.failures, task_id, reason)}
      end

    advance(%{state | running: Map.delete(running, ref)})
  end

  # A delegated Task process crashed before replying.
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{running: running} = state)
      when is_map_key(running, ref) do
    {task_id, running} = Map.pop(running, ref)
    emit_task_stop(state, task_id, :crashed)

    state = %{
      state
      | failures: Map.put(state.failures, task_id, {:crashed, reason}),
        running: running
    }

    advance(state)
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- DAG dispatch ---

  defp advance(state) do
    state = dispatch_ready(state)

    if settled?(state) do
      complete(state)
    else
      {:noreply, state}
    end
  end

  defp dispatch_ready(%{status: :running} = state) do
    pending =
      for {id, task} <- state.tasks,
          not done?(state, id),
          not running?(state, id),
          do: task

    Enum.reduce(pending, state, fn task, acc ->
      cond do
        blocked?(acc, task) -> put_failure(acc, task.id, :dependency_failed)
        deps_ready?(acc, task) -> dispatch_one(acc, task)
        true -> acc
      end
    end)
  end

  # Paused/aborted/completed: don't dispatch new work.
  defp dispatch_ready(state), do: state

  defp dispatch_one(state, task) do
    ctx = Map.put(state.spec.delegation_ctx, :counter, state.rr_counter)

    case Delegation.select(state.spec.strategy, task, state.agents, ctx) do
      {:ok, %Delegation.Result{selected_agent: name}} ->
        agent = Enum.find(state.agents, &(&1.name == name))
        task_sup = Supervisor.via(state.spec.name, :task_sup)

        :telemetry.execute(
          [:agentsea, :crew, :task, :start],
          %{system_time: System.system_time()},
          %{crew: state.spec.name, task_id: task.id, agent: name}
        )

        t =
          Task.Supervisor.async_nolink(task_sup, fn ->
            {:task_done, task.id, AgentSea.Agent.run(agent.pid, CrewTask.input(task))}
          end)

        %{
          state
          | running: Map.put(state.running, t.ref, task.id),
            rr_counter: state.rr_counter + 1
        }

      {:error, reason} ->
        put_failure(state, task.id, {:delegation_failed, reason})
    end
  end

  defp complete(state) do
    result = %{
      success: map_size(state.failures) == 0,
      results: state.results,
      failures: state.failures
    }

    emit_kickoff_stop(state, result.success)

    if state.caller, do: GenServer.reply(state.caller, {:ok, result})
    {:noreply, %{state | status: :completed, caller: nil}}
  end

  defp emit_kickoff_stop(state, success) do
    duration =
      if state.kickoff_started, do: System.monotonic_time() - state.kickoff_started, else: 0

    :telemetry.execute(
      [:agentsea, :crew, :kickoff, :stop],
      %{duration: duration},
      %{crew: state.spec.name, success: success, task_count: map_size(state.tasks)}
    )
  end

  # --- Predicates / helpers ---

  defp settled?(state) do
    map_size(state.running) == 0 and
      Enum.all?(state.tasks, fn {id, _task} -> done?(state, id) end)
  end

  defp done?(state, id),
    do: Map.has_key?(state.results, id) or Map.has_key?(state.failures, id)

  defp running?(state, id), do: id in Map.values(state.running)

  defp deps_ready?(state, %CrewTask{depends_on: deps}),
    do: Enum.all?(deps, &Map.has_key?(state.results, &1))

  defp blocked?(state, %CrewTask{depends_on: deps}) do
    Enum.any?(deps, fn dep ->
      Map.has_key?(state.failures, dep) or not Map.has_key?(state.tasks, dep)
    end)
  end

  defp put_failure(state, id, reason),
    do: %{state | failures: Map.put(state.failures, id, reason)}

  defp emit_task_stop(state, task_id, outcome) do
    :telemetry.execute(
      [:agentsea, :crew, :task, :stop],
      %{system_time: System.system_time()},
      %{crew: state.spec.name, task_id: task_id, outcome: outcome}
    )
  end
end
