defmodule Blitzkeys.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :blitzkeys

  require Logger

  def create do
    load_app()

    for repo <- repos() do
      :ok = ensure_repo_created(repo)
    end
  end

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp ensure_repo_created(repo) do
    Logger.info("Creating database for #{inspect(repo)}")

    case repo.__adapter__.storage_up(repo.config()) do
      :ok ->
        Logger.info("Database created successfully")
        :ok

      {:error, :already_up} ->
        Logger.info("Database already exists")
        :ok

      {:error, term} ->
        Logger.error("Failed to create database: #{inspect(term)}")
        {:error, term}
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
