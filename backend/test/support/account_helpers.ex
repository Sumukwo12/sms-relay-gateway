defmodule Backend.AccountHelpers do
  @moduledoc "Test helpers for accounts. The first registered account is always an admin."

  alias Backend.{Accounts, Repo}
  alias Backend.Accounts.User

  @password "correct horse battery"

  def password, do: @password

  def admin_fixture(attrs \\ %{}) do
    {:ok, user} = register(attrs)
    user |> Ecto.Changeset.change(role: "admin", status: "approved") |> Repo.update!()
  end

  @doc "A regular user, `pending` unless `status:` is given."
  def user_fixture(attrs \\ %{}) do
    # Make sure this account isn't the first (which would become admin)
    unless Repo.exists?(User), do: admin_fixture(%{email: "first-admin@example.com"})

    {status, attrs} = Map.pop(Map.new(attrs), :status, "pending")
    {:ok, user} = register(attrs)
    user |> Ecto.Changeset.change(status: status) |> Repo.update!()
  end

  defp register(attrs) do
    Accounts.register(
      Map.merge(
        %{email: "user#{System.unique_integer([:positive])}@example.com", password: @password},
        Map.new(attrs)
      )
    )
  end
end
