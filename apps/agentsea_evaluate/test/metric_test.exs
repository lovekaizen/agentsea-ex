defmodule AgentSea.Evaluate.MetricTest do
  use ExUnit.Case, async: true

  import Mox

  alias AgentSea.Evaluate.Metric.{ExactMatch, Contains, LLMJudge}
  alias AgentSea.Response

  setup :verify_on_exit!

  describe "ExactMatch" do
    test "passes on a normalized exact match" do
      assert %{score: 1.0, passed: true} =
               ExactMatch.evaluate(%{output: " Paris ", expected: "paris"}, [])
    end

    test "fails when different" do
      result = ExactMatch.evaluate(%{output: "London", expected: "Paris"}, [])
      assert result.score == 0.0
      refute result.passed
    end
  end

  describe "Contains" do
    test "passes when the expected substring is present" do
      assert %{score: 1.0, passed: true} =
               Contains.evaluate(%{output: "The capital is Paris.", expected: "paris"}, [])
    end

    test "fails otherwise" do
      result = Contains.evaluate(%{output: "The capital is Berlin.", expected: "Paris"}, [])
      assert result.score == 0.0
      refute result.passed
    end
  end

  describe "LLMJudge" do
    test "scores from the model's numeric verdict" do
      expect(AgentSea.Evaluate.MockProvider, :complete, fn messages, opts ->
        assert opts[:model] == "judge-model"
        # The rubric/system prompt should be present.
        assert Enum.any?(messages, &(&1.role == :system))
        {:ok, %Response{content: "0.9", stop_reason: :stop}}
      end)

      result =
        LLMJudge.evaluate(
          %{input: "q", output: "a", expected: "a"},
          provider: {AgentSea.Evaluate.MockProvider, []},
          model: "judge-model",
          threshold: 0.8
        )

      assert result.score == 0.9
      assert result.passed
    end

    test "fails below threshold and clamps out-of-range scores" do
      stub(AgentSea.Evaluate.MockProvider, :complete, fn _messages, _opts ->
        {:ok, %Response{content: "The score is 0.2 out of 1", stop_reason: :stop}}
      end)

      result =
        LLMJudge.evaluate(%{output: "a"},
          provider: {AgentSea.Evaluate.MockProvider, []},
          model: "m"
        )

      assert result.score == 0.2
      refute result.passed
    end

    test "scores 0 on a provider error" do
      expect(AgentSea.Evaluate.MockProvider, :complete, fn _m, _o -> {:error, :down} end)

      result =
        LLMJudge.evaluate(%{output: "a"},
          provider: {AgentSea.Evaluate.MockProvider, []},
          model: "m"
        )

      assert result == %{score: 0.0, passed: false}
    end
  end
end
