defmodule Backend.PhoneUtilsTest do
  use ExUnit.Case, async: true

  alias Backend.PhoneUtils

  describe "normalize/1" do
    test "accepts international and local Kenyan formats" do
      for input <- [
            "+254712345678",
            "+254 712 345 678",
            "0712345678",
            "0712 345 678",
            "712345678",
            "254712345678",
            "00254712345678"
          ] do
        assert PhoneUtils.normalize(input) == {:ok, "+254712345678"}, input
      end
    end

    test "keeps other countries in international format" do
      assert PhoneUtils.normalize("+447911123456") == {:ok, "+447911123456"}
    end

    test "rejects what can.t be a phone number" do
      for bad <- ["07123", "12345", "+0712345678", "abc", "", nil, 254_712_345_678] do
        assert PhoneUtils.normalize(bad) == {:error, :invalid_phone}, inspect(bad)
      end
    end
  end

  describe "mask/1" do
    test "masks Kenya phone numbers keeping +2547 prefix and last 3 digits" do
      assert PhoneUtils.mask("+254712345535") == "+2547•••••535"
      assert PhoneUtils.mask("+254712345678") == "+2547•••••678"
    end

    test "masks US (+1) numbers keeping country code and last 3 digits" do
      assert PhoneUtils.mask("+12025550123") == "+1•••••••123"
    end

    test "masks UK (+44) numbers keeping country code and last 3 digits" do
      assert PhoneUtils.mask("+447911123456") == "+44•••••••456"
    end

    test "handles formatted numbers by stripping punctuation" do
      assert PhoneUtils.mask("+254 (712) 345-535") == "+2547•••••535"
    end
  end
end
