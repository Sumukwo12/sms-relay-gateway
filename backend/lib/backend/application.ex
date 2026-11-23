defmodule Backend.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BackendWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:backend, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Backend.PubSub},
      # SQLite outbox of messages from integrated systems
      Backend.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:backend, :ecto_repos),
       skip: not Application.get_env(:backend, :run_migrations_on_boot, true)},
      # Create or promote the server admin from ADMIN_EMAIL / ADMIN_PASSWORD
      {Task, &Backend.Accounts.ensure_admin/0},
      # Background jobs (alert notifications)
      {Task.Supervisor, name: Backend.TaskSupervisor},
      # Cachex store for rate limiting (sliding window)
      Supervisor.child_spec({Cachex, name: :rate_limit_store}, id: :rate_limit_store),
      # SMS transport (USB GSM modem, or the mock in dev/test)
      Backend.Modem,
      # Sends queued /v1 messages through the modem, one at a time
      Backend.Outbox,
      # Delivers stored webhooks to integrated systems, with retries
      Backend.Webhooks,
      # Alerts when the phone is offline, the queue is stuck, battery is low…
      Backend.Monitor,
      # Deletes expired codes and old messages
      Backend.Janitor,
      # Start to serve requests, typically the last entry
      BackendWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Backend.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BackendWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
