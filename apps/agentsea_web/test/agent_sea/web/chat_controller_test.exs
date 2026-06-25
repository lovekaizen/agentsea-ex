defmodule AgentSea.Web.ChatControllerTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  alias AgentSea.Gateway
  alias AgentSea.Gateway.{Config, Provider}
  alias AgentSea.Gateway.Router.Failover

  @endpoint AgentSea.Web.Endpoint

  setup do
    # Start a gateway registered under the name the controller resolves.
    providers = [
      %Provider{name: :test, module: AgentSea.Web.TestProvider, model: "gpt-4"}
    ]

    config = %Config{providers: providers, strategy: Failover}

    start_supervised!(%{
      id: :web_gateway,
      start: {Gateway, :start_link, [config, [name: AgentSea.Web.Gateway]]}
    })

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  defp post_json(conn, path, params) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(params))
  end

  test "returns an OpenAI-shaped chat completion", %{conn: conn} do
    conn =
      post_json(conn, "/v1/chat/completions", %{
        model: "gpt-4",
        messages: [%{role: "user", content: "hi"}]
      })

    body = json_response(conn, 200)

    assert body["object"] == "chat.completion"
    assert body["model"] == "gpt-4"
    assert String.starts_with?(body["id"], "chatcmpl-")

    assert [choice] = body["choices"]
    assert choice["message"]["role"] == "assistant"
    assert choice["message"]["content"] == "Hello there friend"
    assert choice["finish_reason"] == "stop"

    assert body["usage"] == %{
             "prompt_tokens" => 7,
             "completion_tokens" => 3,
             "total_tokens" => 10
           }
  end

  test "streams the completion as Server-Sent Events when stream: true", %{conn: conn} do
    conn =
      post_json(conn, "/v1/chat/completions", %{
        model: "gpt-4",
        messages: [%{role: "user", content: "hi"}],
        stream: true
      })

    assert conn.status == 200
    assert {"content-type", "text/event-stream; charset=utf-8"} in conn.resp_headers

    body = conn.resp_body
    assert body =~ "chat.completion.chunk"
    # Each provider stream event becomes its own delta chunk (real streaming).
    assert body =~ ~s("content":"Hello")
    assert body =~ ~s("content":"there")
    assert body =~ ~s("content":"friend")
    assert body =~ ~s("finish_reason":"stop")
    assert String.ends_with?(String.trim_trailing(body), "data: [DONE]")
  end

  test "returns 502 when the gateway has no available provider", %{conn: conn} do
    # Replace the gateway with one whose provider always errors.
    failing = %Provider{name: :bad, module: __MODULE__.FailingProvider, model: "gpt-4"}
    config = %Config{providers: [failing], strategy: Failover}

    # Stop the good gateway and start a failing one under the same name.
    stop_supervised!(:web_gateway)

    start_supervised!(%{
      id: :failing_gateway,
      start: {Gateway, :start_link, [config, [name: AgentSea.Web.Gateway]]}
    })

    conn =
      post_json(conn, "/v1/chat/completions", %{
        model: "gpt-4",
        messages: [%{role: "user", content: "hi"}]
      })

    body = json_response(conn, 502)
    assert body["error"]["type"] == "gateway_error"
  end

  defmodule FailingProvider do
    @behaviour AgentSea.Provider
    @impl true
    def complete(_messages, _opts), do: {:error, :boom}
    @impl true
    def model_info(_model), do: nil
  end
end
