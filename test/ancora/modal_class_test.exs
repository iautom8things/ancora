defmodule Ancora.ModalClassTest do
  use ExUnit.Case, async: true

  alias Ancora.ModalClass

  describe "classify/1" do
    test "classifies strong positive modals" do
      assert ModalClass.classify("The system MUST reject invalid input.") == :must
      assert ModalClass.classify("The system SHALL validate the request.") == :shall
    end

    test "classifies strong negative modals" do
      assert ModalClass.classify("The system MUST NOT accept unsigned tokens.") == :must_not
      assert ModalClass.classify("The system SHALL NOT expose raw IDs.") == :shall_not
    end

    test "classifies weak modals" do
      assert ModalClass.classify("The system should log a warning.") == :should
      assert ModalClass.classify("The system may redact PII.") == :may
    end

    test "returns :none for statements without a modal verb" do
      assert ModalClass.classify("The system logs a warning.") == :none
      assert ModalClass.classify("") == :none
    end

    test "is case-insensitive and punctuation-insensitive" do
      assert ModalClass.classify("the system must reject input") == :must
      assert ModalClass.classify("THE SYSTEM MUST REJECT INPUT") == :must
      assert ModalClass.classify("The system MUST reject X.") == :must
    end

    test "negative forms take precedence over positive forms" do
      assert ModalClass.classify("The system MUST NOT do X but must log.") == :must_not
    end
  end

  describe "downgrade?/2" do
    test "is total over the 7 x 7 Cartesian product without raising" do
      for prior <- ModalClass.modals(), current <- ModalClass.modals() do
        result = ModalClass.downgrade?(prior, current)
        assert is_boolean(result)
      end
    end

    test "must to should is a downgrade; should to must is not" do
      assert ModalClass.downgrade?(:must, :should)
      refute ModalClass.downgrade?(:should, :must)
    end

    test "identity and :none-origin are never downgrades" do
      for m <- ModalClass.modals() do
        refute ModalClass.downgrade?(m, m)
        refute ModalClass.downgrade?(:none, m)
      end
    end

    test "positive to negative is a downgrade; negative to positive is not" do
      assert ModalClass.downgrade?(:must, :must_not)
      refute ModalClass.downgrade?(:must_not, :must)
    end
  end
end
