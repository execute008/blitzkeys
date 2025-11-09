defmodule BlitzkeysWeb.RoomLive do
  use BlitzkeysWeb, :live_view

  alias Blitzkeys.Rooms.Room
  alias BlitzkeysWeb.Presence
  alias Phoenix.PubSub

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    case Room.whereis(code) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Room not found")
         |> push_navigate(to: ~p"/")}

      _pid ->
        if connected?(socket) do
          # Subscribe to room updates
          PubSub.subscribe(Blitzkeys.PubSub, "room:#{code}")

          # Generate player ID and track presence
          player_id = generate_player_id()
          nickname = generate_nickname()

          {:ok, _} =
            Presence.track(self(), "room:#{code}", player_id, %{
              nickname: nickname,
              joined_at: System.system_time(:second)
            })

          room_state = Room.get_state(code)

          socket =
            socket
            |> assign(
              code: code,
              player_id: player_id,
              nickname: nickname,
              room_state: room_state,
              players: %{},
              input_text: "",
              errors: 0,
              started_at: nil,
              finished_at: nil,
              wpm: 0
            )
            |> handle_presence_diff(Presence.list("room:#{code}"))

          {:ok, socket}
        else
          {:ok, assign(socket, code: code, player_id: nil)}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="container mx-auto px-4 py-8 max-w-6xl">
        <%!-- Room Header --%>
        <div class="mb-8">
          <div class="flex justify-between items-center">
            <div>
              <h1 class="text-3xl font-bold">Room: {@code}</h1>
              <p class="text-base-content/60">Share this code with friends to play together</p>
            </div>
            <.link navigate={~p"/"} class="btn btn-ghost">
              <.icon name="hero-arrow-left" class="w-5 h-5 mr-2" /> Leave Room
            </.link>
          </div>
        </div>

        <%!-- Render based on room state --%>
        <%= case @room_state.status do %>
          <% :lobby -> %>
            <.lobby_view {assigns} />
          <% :countdown -> %>
            <.countdown_view {assigns} />
          <% :playing -> %>
            <.game_view {assigns} />
          <% :results -> %>
            <.results_view {assigns} />
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # Lobby View Component
  defp lobby_view(assigns) do
    ~H"""
    <div class="grid md:grid-cols-2 gap-8">
      <%!-- Players List --%>
      <div class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title">
            <.icon name="hero-users" class="w-6 h-6" /> Players ({map_size(@players)})
          </h2>
          <div class="space-y-2">
            <%= for {id, player} <- @players do %>
              <div class="flex items-center justify-between p-3 bg-base-300 rounded-lg">
                <div class="flex items-center gap-3">
                  <div class="avatar placeholder">
                    <div class="bg-primary text-primary-content rounded-full w-10">
                      <span class="text-lg">{String.first(player.nickname)}</span>
                    </div>
                  </div>
                  <span class="font-medium">{player.nickname}</span>
                  <%= if id == @player_id do %>
                    <span class="badge badge-sm badge-primary">You</span>
                  <% end %>
                </div>
                <div class="w-3 h-3 rounded-full bg-success"></div>
              </div>
            <% end %>
          </div>

          <%= if map_size(@players) < 2 do %>
            <div class="alert alert-info mt-4">
              <.icon name="hero-information-circle" class="w-5 h-5" />
              <span>Waiting for at least one more player...</span>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Settings --%>
      <div class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title">
            <.icon name="hero-cog-6-tooth" class="w-6 h-6" /> Game Settings
          </h2>

          <div class="space-y-4">
            <div class="form-control">
              <label class="label">
                <span class="label-text">Language</span>
              </label>
              <select class="select select-bordered" phx-change="update_language">
                <option value="english" selected={@room_state.settings.language == :english}>
                  English
                </option>
                <option value="spanish" selected={@room_state.settings.language == :spanish}>
                  Spanish
                </option>
                <option value="german" selected={@room_state.settings.language == :german}>
                  German
                </option>
              </select>
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">Rounds</span>
              </label>
              <select class="select select-bordered" phx-change="update_rounds">
                <option value="1" selected={@room_state.settings.total_rounds == 1}>Best of 1</option>
                <option value="3" selected={@room_state.settings.total_rounds == 3}>Best of 3</option>
                <option value="5" selected={@room_state.settings.total_rounds == 5}>Best of 5</option>
              </select>
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">Difficulty</span>
              </label>
              <select class="select select-bordered" phx-change="update_difficulty">
                <option
                  value="common_words"
                  selected={@room_state.settings.text_difficulty == :common_words}
                >
                  Common Words
                </option>
                <option value="quotes" selected={@room_state.settings.text_difficulty == :quotes}>
                  Quotes
                </option>
                <option value="code" selected={@room_state.settings.text_difficulty == :code}>
                  Code
                </option>
              </select>
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">Scoring Mode</span>
              </label>
              <select class="select select-bordered" phx-change="update_scoring">
                <option value="wpm" selected={@room_state.settings.scoring_mode == :wpm}>
                  Words Per Minute
                </option>
                <option
                  value="wpm_accuracy"
                  selected={@room_state.settings.scoring_mode == :wpm_accuracy}
                >
                  WPM + Accuracy
                </option>
              </select>
            </div>
          </div>

          <%= if map_size(@players) >= 2 do %>
            <button phx-click="start_game" class="btn btn-primary btn-block mt-6">
              <.icon name="hero-play" class="w-5 h-5 mr-2" /> Start Game
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Countdown View Component
  defp countdown_view(assigns) do
    ~H"""
    <div class="flex items-center justify-center min-h-[400px]">
      <div class="text-center">
        <h2 class="text-6xl font-bold mb-4">Get Ready!</h2>
        <p class="text-2xl text-base-content/60">Game starting in...</p>
        <div class="text-9xl font-bold text-primary mt-8 animate-pulse">3</div>
      </div>
    </div>
    """
  end

  # Game View Component
  defp game_view(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Progress Bars for all players --%>
      <div class="card bg-base-200">
        <div class="card-body">
          <h3 class="card-title mb-4">Race Progress</h3>
          <div class="space-y-3">
            <%= for {id, player} <- @players do %>
              <div>
                <div class="flex justify-between text-sm mb-1">
                  <span class="font-medium">{player.nickname}</span>
                  <span class="text-base-content/60">{player[:progress] || 0}%</span>
                </div>
                <progress
                  class="progress progress-primary w-full"
                  value={player[:progress] || 0}
                  max="100"
                >
                </progress>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Typing Interface --%>
      <div class="card bg-base-200">
        <div class="card-body">
          <div class="mb-6">
            <div class="flex justify-between items-center mb-4">
              <h3 class="text-lg font-semibold">Type the text below:</h3>
              <div class="stats shadow">
                <div class="stat py-2 px-4">
                  <div class="stat-title text-xs">WPM</div>
                  <div class="stat-value text-2xl">{@wpm}</div>
                </div>
                <div class="stat py-2 px-4">
                  <div class="stat-title text-xs">Errors</div>
                  <div class="stat-value text-2xl">{@errors}</div>
                </div>
              </div>
            </div>

            <%!-- Text to type --%>
            <div class="bg-base-300 p-6 rounded-lg mb-4">
              <p class="text-xl font-mono leading-relaxed">{@room_state.current_text}</p>
            </div>

            <%!-- Input area --%>
            <input
              id="typing-input"
              type="text"
              phx-keyup="type"
              value={@input_text}
              class="input input-bordered input-lg w-full font-mono"
              placeholder="Start typing..."
              autocomplete="off"
              autocorrect="off"
              spellcheck="false"
              phx-hook="TypingInput"
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Results View Component
  defp results_view(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body">
        <h2 class="card-title text-3xl mb-6">
          <.icon name="hero-trophy" class="w-8 h-8 text-warning" /> Results
        </h2>

        <div class="overflow-x-auto">
          <table class="table">
            <thead>
              <tr>
                <th>Rank</th>
                <th>Player</th>
                <th>WPM</th>
                <th>Accuracy</th>
                <th>Time</th>
              </tr>
            </thead>
            <tbody>
              <%= for {player, index} <- Enum.with_index(@players |> Enum.to_list(), 1) do %>
                <tr class={if elem(player, 0) == @player_id, do: "bg-primary/10"}>
                  <td>
                    <%= if index == 1 do %>
                      <.icon name="hero-trophy" class="w-6 h-6 text-warning" />
                    <% else %>
                      {index}
                    <% end %>
                  </td>
                  <td class="font-medium">{elem(player, 1).nickname}</td>
                  <td>{elem(player, 1)[:stats][:wpm] || 0}</td>
                  <td>{elem(player, 1)[:stats][:accuracy] || 0}%</td>
                  <td>{elem(player, 1)[:stats][:time] || 0}s</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <div class="card-actions justify-end mt-6">
          <button phx-click="play_again" class="btn btn-primary">
            Play Again
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("update_language", %{"value" => lang}, socket) do
    update_room_settings(socket, %{language: String.to_existing_atom(lang)})
  end

  @impl true
  def handle_event("update_rounds", %{"value" => rounds}, socket) do
    update_room_settings(socket, %{total_rounds: String.to_integer(rounds)})
  end

  @impl true
  def handle_event("update_difficulty", %{"value" => diff}, socket) do
    update_room_settings(socket, %{text_difficulty: String.to_existing_atom(diff)})
  end

  @impl true
  def handle_event("update_scoring", %{"value" => mode}, socket) do
    update_room_settings(socket, %{scoring_mode: String.to_existing_atom(mode)})
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    case Room.start_game(socket.assigns.code) do
      :ok -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Cannot start: #{reason}")}
    end
  end

  @impl true
  def handle_event("type", %{"key" => _key, "value" => value}, socket) do
    # Calculate progress and WPM
    target_text = socket.assigns.room_state.current_text
    progress = calculate_progress(value, target_text)

    # Update local state
    socket = assign(socket, input_text: value, wpm: calculate_wpm(socket, value))

    # Broadcast progress
    Room.update_progress(socket.assigns.code, socket.assigns.player_id, progress)

    # Check if finished
    if progress >= 100 do
      stats = %{
        wpm: socket.assigns.wpm,
        accuracy: calculate_accuracy(value, target_text),
        time: calculate_time(socket)
      }

      Room.player_finished(socket.assigns.code, socket.assigns.player_id, stats)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("play_again", _params, socket) do
    {:noreply, socket}
  end

  # PubSub Message Handlers

  @impl true
  def handle_info(%{event: "presence_diff", payload: %{joins: joins, leaves: leaves}}, socket) do
    socket =
      socket
      |> add_players(joins)
      |> remove_players(leaves)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:settings_updated, settings}, socket) do
    room_state = %{socket.assigns.room_state | settings: settings}
    {:noreply, assign(socket, room_state: room_state)}
  end

  @impl true
  def handle_info({:game_starting, _data}, socket) do
    room_state = Room.get_state(socket.assigns.code)
    {:noreply, assign(socket, room_state: room_state)}
  end

  @impl true
  def handle_info({:game_started, %{text: text}}, socket) do
    room_state = %{socket.assigns.room_state | status: :playing, current_text: text}

    socket =
      socket
      |> assign(room_state: room_state, started_at: System.monotonic_time(:millisecond))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:player_progress, player_id, progress}, socket) do
    players = put_in(socket.assigns.players, [player_id, :progress], progress)
    {:noreply, assign(socket, players: players)}
  end

  @impl true
  def handle_info({:player_finished, player_id, stats}, socket) do
    players = put_in(socket.assigns.players, [player_id, :stats], stats)
    {:noreply, assign(socket, players: players)}
  end

  @impl true
  def handle_info({:results, _results}, socket) do
    room_state = %{socket.assigns.room_state | status: :results}
    {:noreply, assign(socket, room_state: room_state)}
  end

  @impl true
  def handle_info({:game_over, _results}, socket) do
    {:noreply, socket}
  end

  # Private Helpers

  defp update_room_settings(socket, settings) do
    case Room.update_settings(socket.assigns.code, settings) do
      {:ok, _} -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Cannot update: #{reason}")}
    end
  end

  defp handle_presence_diff(socket, presences) do
    players =
      presences
      |> Enum.into(%{}, fn {id, %{metas: [meta | _]}} ->
        {id, %{nickname: meta.nickname, joined_at: meta.joined_at}}
      end)

    assign(socket, players: players)
  end

  defp add_players(socket, joins) do
    new_players =
      joins
      |> Enum.into(%{}, fn {id, %{metas: [meta | _]}} ->
        {id, %{nickname: meta.nickname, joined_at: meta.joined_at}}
      end)

    assign(socket, players: Map.merge(socket.assigns.players, new_players))
  end

  defp remove_players(socket, leaves) do
    player_ids = Map.keys(leaves)
    assign(socket, players: Map.drop(socket.assigns.players, player_ids))
  end

  defp generate_player_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end

  defp generate_nickname do
    adjectives = ["Swift", "Quick", "Fast", "Rapid", "Speedy", "Lightning", "Turbo", "Blazing"]
    nouns = ["Typer", "Racer", "Champ", "Master", "Ace", "Pro", "Wizard", "Ninja"]

    "#{Enum.random(adjectives)}#{Enum.random(nouns)}"
  end

  defp calculate_progress(input, target) do
    if target == "" do
      0
    else
      min(100, div(String.length(input) * 100, String.length(target)))
    end
  end

  defp calculate_wpm(socket, input) do
    if socket.assigns.started_at do
      elapsed_minutes = (System.monotonic_time(:millisecond) - socket.assigns.started_at) / 60_000
      words = String.split(input, " ") |> length()

      if elapsed_minutes > 0 do
        round(words / elapsed_minutes)
      else
        0
      end
    else
      0
    end
  end

  defp calculate_accuracy(input, target) do
    if String.length(input) == 0 do
      100
    else
      correct_chars =
        String.graphemes(input)
        |> Enum.zip(String.graphemes(target))
        |> Enum.count(fn {a, b} -> a == b end)

      round(correct_chars / String.length(input) * 100)
    end
  end

  defp calculate_time(socket) do
    if socket.assigns.started_at do
      round((System.monotonic_time(:millisecond) - socket.assigns.started_at) / 1000)
    else
      0
    end
  end
end
