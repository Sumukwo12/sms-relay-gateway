defmodule Backend.SegmentsTest do
  use ExUnit.Case, async: true

  alias Backend.Segments

  test "plain GSM-7 text: 160 fit in one SMS, then 153 per part" do
    assert Segments.count("") == 1
    assert Segments.count(String.duplicate("a", 160)) == 1
    assert Segments.count(String.duplicate("a", 161)) == 2
    assert Segments.count(String.duplicate("a", 306)) == 2
    assert Segments.count(String.duplicate("a", 307)) == 3
    assert Segments.count(String.duplicate("a", 480)) == 4
  end

  test "extension characters take two slots" do
    assert Segments.gsm7?("Price: €5 [promo]")
    assert Segments.count(String.duplicate("€", 80)) == 1
    assert Segments.count(String.duplicate("€", 81)) == 2
  end

  test "anything outside GSM-7 switches the whole message to UCS-2" do
    refute Segments.gsm7?("Habari 👋")
    assert Segments.count(String.duplicate("ж", 70)) == 1
    assert Segments.count(String.duplicate("ж", 71)) == 2
    assert Segments.count(String.duplicate("ж", 134)) == 2
    assert Segments.count(String.duplicate("ж", 135)) == 3
    # An emoji is two UTF-16 code units
    assert Segments.count(String.duplicate("👋", 35)) == 1
    assert Segments.count(String.duplicate("👋", 36)) == 2
  end
end
