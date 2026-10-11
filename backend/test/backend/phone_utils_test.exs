defmodule Backend.PhoneUtilsTest do
  use ExUnit.Case, async: true

  alias Backend.PhoneUtils

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
