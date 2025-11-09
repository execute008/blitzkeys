defmodule Blitzkeys.Rooms.Room do
  @moduledoc """
  GenServer that manages the state of a single typing game room.

  State machine flow:
  :lobby -> :countdown -> :playing -> :results -> :lobby (or terminate)

  Responsibilities:
  - Track connected players
  - Manage game configuration (language, rounds, scoring)
  - Coordinate game state transitions
  - Broadcast updates via PubSub
  """
  use GenServer
  require Logger

  alias Phoenix.PubSub
  alias Blitzkeys.TextGenerator
  alias BlitzkeysWeb.Presence

  @idle_timeout :timer.hours(1)

  # Client API

  def start_link({code, settings}) do
    GenServer.start_link(__MODULE__, {code, settings}, name: via_tuple(code))
  end

  @doc "Returns the PID for a room code, or nil if not found"
  def whereis(code) do
    case Registry.lookup(Blitzkeys.Rooms.Registry, code) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "Gets the current state of the room"
  def get_state(code) do
    code |> via_tuple() |> GenServer.call(:get_state)
  end

  @doc "Updates room settings (only allowed in lobby state and by creator)"
  def update_settings(code, player_id, settings) do
    code |> via_tuple() |> GenServer.call({:update_settings, player_id, settings})
  end

  @doc "Sets the creator of the room (first player to join)"
  def set_creator(code, player_id) do
    code |> via_tuple() |> GenServer.call({:set_creator, player_id})
  end

  @doc "Checks and reassigns creator if needed (when players join/leave)"
  def check_creator(code) do
    code |> via_tuple() |> GenServer.cast(:check_creator)
  end

  @doc "Vote to start the game"
  def vote_start(code, player_id) do
    code |> via_tuple() |> GenServer.call({:vote_start, player_id})
  end

  @doc "Vote to play again"
  def vote_play_again(code, player_id) do
    code |> via_tuple() |> GenServer.call({:vote_play_again, player_id})
  end

  @doc "Vote to return to lobby"
  def vote_back_to_lobby(code, player_id) do
    code |> via_tuple() |> GenServer.call({:vote_back_to_lobby, player_id})
  end

  @doc "Validates a typed word and updates player progress"
  def validate_word(code, player_id, typed_word) do
    code |> via_tuple() |> GenServer.call({:validate_word, player_id, typed_word})
  end

  @doc "Gets current game time remaining"
  def get_time_remaining(code) do
    code |> via_tuple() |> GenServer.call(:get_time_remaining)
  end

  # Server Callbacks

  @impl true
  def init({code, settings}) do
    # Subscribe to presence changes to detect when creator leaves
    PubSub.subscribe(Blitzkeys.PubSub, "room:#{code}")

    state = %{
      code: code,
      status: :lobby,
      settings: default_settings(settings),
      players: %{},
      current_text: nil,
      round: 0,
      scores: %{},
      started_at: nil,
      timer_ref: nil,
      time_remaining: nil,
      votes_to_start: MapSet.new(),
      votes_to_play_again: MapSet.new(),
      votes_to_lobby: MapSet.new(),
      countdown: nil,
      creator_id: nil
    }

    Logger.info("Room #{code} created")

    # Notify lobby that a new room was created
    PubSub.broadcast(Blitzkeys.PubSub, "lobby", {:room_created, code})

    {:ok, state, @idle_timeout}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state, @idle_timeout}
  end

  @impl true
  def handle_call({:set_creator, player_id}, _from, %{creator_id: nil} = state) do
    new_state = %{state | creator_id: player_id}
    Logger.info("Room #{state.code} creator set to #{player_id}")
    {:reply, :ok, new_state, @idle_timeout}
  end

  @impl true
  def handle_call({:set_creator, _player_id}, _from, state) do
    # Creator already set, ignore
    {:reply, :ok, state, @idle_timeout}
  end

  @impl true
  def handle_call({:update_settings, player_id, new_settings}, _from, %{status: :lobby} = state) do
    # Get creator_id safely (backward compatibility for old rooms)
    creator_id = Map.get(state, :creator_id)

    # If no creator set, or player is the creator, allow changes
    if creator_id == nil or creator_id == player_id do
      updated_settings = Map.merge(state.settings, new_settings)
      new_state = %{state | settings: updated_settings}

      broadcast(state.code, {:settings_updated, updated_settings})
      {:reply, {:ok, updated_settings}, new_state, @idle_timeout}
    else
      {:reply, {:error, :not_creator}, state, @idle_timeout}
    end
  end

  @impl true
  def handle_call({:update_settings, _player_id, _new_settings}, _from, state) do
    {:reply, {:error, :game_in_progress}, state, @idle_timeout}
  end

  @impl true
  def handle_call({:vote_start, player_id}, _from, %{status: :lobby} = state) do
    votes = MapSet.put(state.votes_to_start, player_id)
    new_state = %{state | votes_to_start: votes}

    # Get current player count from Presence
    player_count =
      "room:#{state.code}"
      |> Presence.list()
      |> map_size()

    # Broadcast vote update
    broadcast(state.code, {:vote_update, :start, MapSet.size(votes), player_count})

    # Check if all players have voted
    if MapSet.size(votes) >= player_count && player_count >= 2 do
      # Everyone voted! Start the game
      send(self(), :all_voted_start)
      {:reply, :ok, new_state, @idle_timeout}
    else
      {:reply, :ok, new_state, @idle_timeout}
    end
  end

  @impl true
  def handle_call({:vote_play_again, player_id}, _from, %{status: :results} = state) do
    votes = MapSet.put(state.votes_to_play_again, player_id)
    new_state = %{state | votes_to_play_again: votes}

    player_count =
      "room:#{state.code}"
      |> Presence.list()
      |> map_size()

    broadcast(state.code, {:vote_update, :play_again, MapSet.size(votes), player_count})

    if MapSet.size(votes) >= player_count && player_count >= 2 do
      send(self(), :all_voted_play_again)
      {:reply, :ok, new_state, @idle_timeout}
    else
      {:reply, :ok, new_state, @idle_timeout}
    end
  end

  @impl true
  def handle_call({:vote_back_to_lobby, player_id}, _from, %{status: :results} = state) do
    votes = MapSet.put(state.votes_to_lobby, player_id)
    new_state = %{state | votes_to_lobby: votes}

    player_count =
      "room:#{state.code}"
      |> Presence.list()
      |> map_size()

    broadcast(state.code, {:vote_update, :back_to_lobby, MapSet.size(votes), player_count})

    if MapSet.size(votes) >= player_count && player_count >= 1 do
      send(self(), :all_voted_lobby)
      {:reply, :ok, new_state, @idle_timeout}
    else
      {:reply, :ok, new_state, @idle_timeout}
    end
  end

  @impl true
  def handle_call(:old_start_game, _from, %{status: :lobby} = state) do
    # Get current players from Presence
    players =
      "room:#{state.code}"
      |> Presence.list()
      |> Enum.into(%{}, fn {id, _data} -> {id, %{}} end)

    if map_size(players) < 2 do
      {:reply, {:error, :not_enough_players}, state, @idle_timeout}
    else
      # Generate text based on settings
      text = generate_text(state.settings)

      # Initialize player tracking with word-based progress
      players_with_progress =
        Enum.into(players, %{}, fn {id, _} ->
          {id, %{current_word_index: 0, correct_words: [], incorrect_words: []}}
        end)

      new_state = %{
        state
        | status: :countdown,
          current_text: text,
          round: state.round + 1,
          players: players_with_progress,
          timer_ref: nil,
          time_remaining: state.settings.timer_seconds
      }

      broadcast(state.code, {:game_starting, %{countdown: 3}})
      schedule_countdown(state.code)

      {:reply, :ok, new_state, @idle_timeout}
    end
  end

  @impl true
  def handle_call(:start_game, _from, state) do
    {:reply, {:error, :game_already_started}, state, @idle_timeout}
  end

  @impl true
  def handle_call({:validate_word, player_id, typed_word}, _from, %{status: :playing} = state) do
    player = state.players[player_id]

    if player do
      current_index = player.current_word_index
      correct_word = Enum.at(state.current_text, current_index)

      is_correct = typed_word == correct_word

      updated_player =
        if is_correct do
          %{
            player
            | current_word_index: current_index + 1,
              correct_words: [typed_word | player.correct_words]
          }
        else
          %{
            player
            | current_word_index: current_index + 1,
              incorrect_words: [typed_word | player.incorrect_words]
          }
        end

      updated_players = Map.put(state.players, player_id, updated_player)
      new_state = %{state | players: updated_players}

      # Broadcast word result to all players
      broadcast(state.code, {:word_validated, player_id, current_index, is_correct})

      {:reply, {:ok, is_correct, updated_player.current_word_index}, new_state, @idle_timeout}
    else
      {:reply, {:error, :player_not_found}, state, @idle_timeout}
    end
  end

  @impl true
  def handle_call({:validate_word, _player_id, _typed_word}, _from, state) do
    {:reply, {:error, :game_not_playing}, state, @idle_timeout}
  end

  @impl true
  def handle_call(:get_time_remaining, _from, state) do
    {:reply, state.time_remaining || 0, state, @idle_timeout}
  end

  @impl true
  def handle_cast(:check_creator, state) do
    # Get current players from Presence
    current_players =
      "room:#{state.code}"
      |> Presence.list()
      |> Map.keys()

    creator_id = Map.get(state, :creator_id)

    cond do
      # No creator set yet, do nothing
      creator_id == nil ->
        {:noreply, state, @idle_timeout}

      # Creator is still in the room, do nothing
      creator_id in current_players ->
        {:noreply, state, @idle_timeout}

      # Creator left, reassign to first available player
      length(current_players) > 0 ->
        new_creator = List.first(current_players)
        new_state = %{state | creator_id: new_creator}

        Logger.info(
          "Room #{state.code}: Creator left, reassigning from #{creator_id} to #{new_creator}"
        )

        broadcast(state.code, {:creator_changed, new_creator})
        {:noreply, new_state, @idle_timeout}

      # No players left, clear creator
      true ->
        new_state = %{state | creator_id: nil}
        {:noreply, new_state, @idle_timeout}
    end
  end

  @impl true
  def handle_info(:all_voted_start, state) when state.status in [:lobby, :results] do
    # Get current players from Presence
    players =
      "room:#{state.code}"
      |> Presence.list()
      |> Enum.into(%{}, fn {id, _data} -> {id, %{}} end)

    if map_size(players) < 2 do
      {:noreply, state, @idle_timeout}
    else
      # Generate text based on settings
      text = generate_text(state.settings)

      # Initialize player tracking with word-based progress
      players_with_progress =
        Enum.into(players, %{}, fn {id, _} ->
          {id, %{current_word_index: 0, correct_words: [], incorrect_words: []}}
        end)

      new_state = %{
        state
        | status: :countdown,
          current_text: text,
          round: state.round + 1,
          players: players_with_progress,
          timer_ref: nil,
          time_remaining: state.settings.timer_seconds,
          votes_to_start: MapSet.new(),
          votes_to_play_again: MapSet.new(),
          countdown: 3
      }

      broadcast(state.code, {:game_starting, %{countdown: 3}})
      broadcast_lobby_update(state.code)
      schedule_countdown_tick(state.code, 2)

      {:noreply, new_state, @idle_timeout}
    end
  end

  @impl true
  def handle_info(:all_voted_play_again, %{status: :results} = state) do
    # Reset and start new game directly (don't change to :lobby)
    send(self(), :all_voted_start)
    {:noreply, state, @idle_timeout}
  end

  @impl true
  def handle_info(:all_voted_lobby, %{status: :results} = state) do
    # Return to lobby
    new_state = %{
      state
      | status: :lobby,
        round: 0,
        scores: %{},
        votes_to_lobby: MapSet.new(),
        votes_to_play_again: MapSet.new()
    }

    broadcast(state.code, {:returned_to_lobby, %{}})
    broadcast_lobby_update(state.code)
    {:noreply, new_state, @idle_timeout}
  end

  @impl true
  def handle_info({:countdown_tick, count}, %{status: :countdown} = state) when count > 0 do
    # Continue countdown
    new_state = %{state | countdown: count}
    broadcast(state.code, {:countdown_update, count})
    schedule_countdown_tick(state.code, count - 1)
    {:noreply, new_state, @idle_timeout}
  end

  @impl true
  def handle_info({:countdown_tick, 0}, %{status: :countdown} = state) do
    # Start the game timer
    timer_ref = schedule_timer_tick(state.code)

    new_state = %{
      state
      | status: :playing,
        started_at: System.monotonic_time(:millisecond),
        timer_ref: timer_ref,
        countdown: nil
    }

    broadcast(state.code, {:game_started, %{words: state.current_text}})
    broadcast_lobby_update(state.code)
    {:noreply, new_state, @idle_timeout}
  end

  @impl true
  def handle_info(:timer_tick, %{status: :playing} = state) do
    new_time = state.time_remaining - 1

    # Broadcast time update every second (including when it reaches 0)
    broadcast(state.code, {:timer_update, new_time})

    if new_time <= 0 do
      # Time's up! End the game
      Logger.info("Timer expired for room #{state.code}")
      if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

      # Show loading state briefly
      broadcast(state.code, {:calculating_results, %{}})

      new_state = %{state | status: :results, time_remaining: 0, timer_ref: nil}
      broadcast_lobby_update(state.code)
      schedule_results(state.code)

      {:noreply, new_state, @idle_timeout}
    else
      # Continue countdown
      timer_ref = schedule_timer_tick(state.code)
      new_state = %{state | time_remaining: new_time, timer_ref: timer_ref}

      {:noreply, new_state, @idle_timeout}
    end
  end

  @impl true
  def handle_info(:timer_tick, state) do
    # Ignore timer ticks if not playing
    {:noreply, state, @idle_timeout}
  end

  @impl true
  def handle_info(:show_results, %{status: :results} = state) do
    results = calculate_results(state)
    broadcast(state.code, {:results, results})

    # Check if more rounds needed
    if state.round < state.settings.total_rounds do
      schedule_next_round(state.code)
      {:noreply, state, @idle_timeout}
    else
      # Game over - stay in :results status so players can vote
      broadcast(state.code, {:game_over, results})
      {:noreply, state, @idle_timeout}
    end
  end

  @impl true
  def handle_info(:next_round, state) do
    {:noreply, %{state | status: :lobby, players: reset_players(state.players)}, @idle_timeout}
  end

  @impl true
  def handle_info(:timeout, state) do
    Logger.info("Room #{state.code} timed out due to inactivity")
    broadcast_lobby_update(state.code)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(%{event: "presence_diff", payload: %{joins: joins, leaves: leaves}}, state) do
    # Check if creator left and reassign if needed
    if map_size(leaves) > 0 do
      send(self(), :check_creator_async)
    end

    # Notify lobby of player count changes
    if map_size(joins) > 0 or map_size(leaves) > 0 do
      PubSub.broadcast(Blitzkeys.PubSub, "lobby", {:room_updated, state.code})
    end

    {:noreply, state, @idle_timeout}
  end

  @impl true
  def handle_info(:check_creator_async, state) do
    # Perform creator check asynchronously
    handle_cast(:check_creator, state)
  end

  # Catch-all for other messages (like broadcasts from itself)
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state, @idle_timeout}
  end

  # Private Helpers

  defp via_tuple(code) do
    {:via, Registry, {Blitzkeys.Rooms.Registry, code}}
  end

  defp broadcast(code, message) do
    PubSub.broadcast(Blitzkeys.PubSub, "room:#{code}", message)
  end

  defp broadcast_lobby_update(code) do
    PubSub.broadcast(Blitzkeys.PubSub, "lobby", {:room_updated, code})
  end

  defp default_settings(custom_settings) do
    %{
      language: :english,
      total_rounds: 1,
      scoring_mode: :wpm,
      text_difficulty: :common_words,
      timer_seconds: 60,
      is_public: true
    }
    |> Map.merge(custom_settings)
  end

  defp generate_text(settings) do
    TextGenerator.generate(%{
      language: settings.language,
      difficulty: settings.text_difficulty,
      word_count: 200
    })
  end

  defp schedule_countdown(code) do
    Process.send_after(whereis(code), :countdown_tick, 3000)
  end

  defp schedule_countdown_tick(code, count) do
    Process.send_after(whereis(code), {:countdown_tick, count}, 1000)
  end

  defp schedule_timer_tick(code) do
    Process.send_after(whereis(code), :timer_tick, 1000)
  end

  defp schedule_results(code) do
    Process.send_after(whereis(code), :show_results, 2000)
  end

  defp schedule_next_round(code) do
    Process.send_after(whereis(code), :next_round, 5000)
  end

  defp calculate_results(state) do
    elapsed_time = state.settings.timer_seconds - state.time_remaining

    results =
      Enum.map(state.players, fn {id, player} ->
        correct_count = length(player.correct_words)
        incorrect_count = length(player.incorrect_words)
        total_words = correct_count + incorrect_count

        wpm =
          if elapsed_time > 0 do
            round(correct_count / (elapsed_time / 60))
          else
            0
          end

        accuracy =
          if total_words > 0 do
            round(correct_count / total_words * 100)
          else
            100
          end

        # Calculate score based on scoring mode
        score =
          case state.settings.scoring_mode do
            :wpm ->
              wpm

            :wpm_accuracy ->
              # Combine WPM and accuracy: WPM * (accuracy/100)
              # This gives higher scores to players with both high WPM and accuracy
              round(wpm * (accuracy / 100))
          end

        %{
          player_id: id,
          correct_words: correct_count,
          incorrect_words: incorrect_count,
          wpm: wpm,
          accuracy: accuracy,
          score: score
        }
      end)

    # Sort by score (highest first)
    Enum.sort_by(results, & &1.score, :desc)
  end

  defp reset_players(players) do
    Enum.into(players, %{}, fn {id, player} ->
      {id, Map.drop(player, [:progress, :finished, :stats])}
    end)
  end
end
