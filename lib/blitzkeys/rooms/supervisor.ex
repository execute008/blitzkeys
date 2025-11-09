defmodule Blitzkeys.Rooms.Supervisor do
  @moduledoc """
  DynamicSupervisor that manages all active typing game rooms.
  Each room is a separate GenServer process that handles game state.
  """
  use DynamicSupervisor

  alias Blitzkeys.Rooms.Room

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Creates a new room with the given code and settings.
  Returns {:ok, pid} or {:error, reason}.
  """
  def create_room(code, settings \\ %{}) do
    spec = {Room, {code, settings}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Terminates a room process.
  """
  def terminate_room(code) do
    case Room.whereis(code) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  @doc """
  Lists all active room codes.
  """
  def list_rooms do
    Registry.select(Blitzkeys.Rooms.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @doc """
  Lists all active rooms with their metadata (code, player count, status).
  Sorted by player count (descending) and then by code.
  Only includes public rooms with at least 1 player.
  """
  def list_rooms_with_info do
    list_rooms()
    |> Enum.map(fn code ->
      case Room.whereis(code) do
        nil ->
          nil

        _pid ->
          state = Room.get_state(code)

          player_count =
            "room:#{code}"
            |> BlitzkeysWeb.Presence.list()
            |> map_size()

          %{
            code: code,
            player_count: player_count,
            status: state.status,
            is_public: Map.get(state.settings, :is_public, true),
            id: "room-#{code}"
          }
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&(&1.player_count > 0 && &1.is_public))
    |> Enum.sort_by(&{-&1.player_count, &1.code})
  end
end
