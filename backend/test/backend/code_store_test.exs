defmodule Backend.CodeStoreTest do
  use Backend.DataCase, async: false

  import Ecto.Query
  alias Backend.{CodeStore, Repo}
  alias Backend.CodeStore.OtpCode

  @phone "+254712345678"

  test "codes are scoped to the system that requested them" do
    :ok = CodeStore.put("billing", @phone, "111111", 300)
    :ok = CodeStore.put("crm", @phone, "222222", 300)

    assert CodeStore.verify("crm", @phone, "111111") == {:error, :invalid_code}
    assert CodeStore.verify("billing", @phone, "111111") == :ok
    assert CodeStore.verify("crm", @phone, "222222") == :ok
  end

  test "stores a hash, not the code" do
    :ok = CodeStore.put("billing", @phone, "123456", 300)
    [stored] = Repo.all(OtpCode)

    refute stored.code_hash =~ "123456"
  end

  test "expired codes don't verify and are purged" do
    :ok = CodeStore.put("billing", @phone, "123456", 300)
    Repo.update_all(OtpCode, set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)])

    assert CodeStore.verify("billing", @phone, "123456") == {:error, :expired_or_missing}
    refute CodeStore.has_pending?("billing", @phone)
    assert CodeStore.purge_expired() == 1
    assert Repo.aggregate(from(c in OtpCode), :count) == 0
  end
end
