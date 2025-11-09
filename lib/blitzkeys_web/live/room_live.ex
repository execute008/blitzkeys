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
        # Get room state for initial render
        room_state = Room.get_state(code)

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

          # Set as creator if this is the first player
          Room.set_creator(code, player_id)

          socket =
            socket
            |> assign(
              code: code,
              player_id: player_id,
              nickname: nickname,
              room_state: room_state,
              players: %{},
              # New 10FF-style assigns
              current_input: "",
              current_word_index: 0,
              typed_words: [],
              time_remaining: nil,
              player_progress: %{},
              results: [],
              # Voting
              votes_start: 0,
              votes_play_again: 0,
              votes_lobby: 0,
              player_count: 0,
              has_voted_start: false,
              has_voted_play_again: false,
              has_voted_lobby: false,
              # Countdown
              countdown: nil,
              # Loading state
              calculating_results: false,
              # Creator check
              is_creator: false,
              # Practice mode
              practice_text: generate_practice_text(),
              practice_input: "",
              practice_word_index: 0,
              practice_typed_words: [],
              practice_started_at: nil,
              practice_wpm: 0,
              practice_accuracy: 100
            )
            |> handle_presence_diff(Presence.list("room:#{code}"))
            |> update_creator_status()

          {:ok, socket}
        else
          # Initial render (not connected yet)
          {:ok,
           assign(socket,
             code: code,
             player_id: nil,
             room_state: room_state,
             players: %{},
             current_input: "",
             current_word_index: 0,
             typed_words: [],
             time_remaining: nil,
             player_progress: %{},
             results: [],
             votes_start: 0,
             votes_play_again: 0,
             votes_lobby: 0,
             player_count: 0,
             has_voted_start: false,
             has_voted_play_again: false,
             has_voted_lobby: false,
             countdown: nil,
             calculating_results: false,
             is_creator: false,
             practice_text: [],
             practice_input: "",
             practice_word_index: 0,
             practice_typed_words: [],
             practice_started_at: nil,
             practice_wpm: 0,
             practice_accuracy: 100
           )}
        end
    end
  end

  @impl true
  def render(assigns) do
    # Only use full width for the playing state
    assigns = assign(assigns, :is_playing, assigns.room_state.status == :playing)

    ~H"""
    <Layouts.app flash={@flash} full_width={@is_playing}>
      <div
        class={[
          "mx-auto",
          if(@is_playing, do: "container", else: "max-w-2xl")
        ]}
        style={if @is_playing, do: "max-width: 1400px;", else: ""}
      >
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
    <div class="space-y-8">
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
                    <%= if id == @room_state.creator_id do %>
                      <span class="badge badge-sm badge-warning">
                        <.icon name="hero-star" class="w-3 h-3 mr-1" /> Creator
                      </span>
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

            <%= if !@is_creator do %>
              <div class="alert alert-info">
                <.icon name="hero-information-circle" class="w-5 h-5" />
                <span>Only the room creator can change settings</span>
              </div>
            <% end %>

            <form phx-change="update_settings" id="settings-form">
              <div class="space-y-4">
                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Language</span>
                  </label>
                  <select
                    class="select select-bordered"
                    name="language"
                    disabled={!@is_creator}
                  >
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
                  <select
                    class="select select-bordered"
                    name="rounds"
                    disabled={!@is_creator}
                  >
                    <option value="1" selected={@room_state.settings.total_rounds == 1}>
                      Best of 1
                    </option>
                    <option value="3" selected={@room_state.settings.total_rounds == 3}>
                      Best of 3
                    </option>
                    <option value="5" selected={@room_state.settings.total_rounds == 5}>
                      Best of 5
                    </option>
                  </select>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Difficulty</span>
                  </label>
                  <select
                    class="select select-bordered"
                    name="difficulty"
                    disabled={!@is_creator}
                  >
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
                    <span class="label-text">Timer Duration</span>
                  </label>
                  <select
                    class="select select-bordered"
                    name="timer"
                    disabled={!@is_creator}
                  >
                    <option value="30" selected={@room_state.settings.timer_seconds == 30}>
                      30 seconds
                    </option>
                    <option value="60" selected={@room_state.settings.timer_seconds == 60}>
                      60 seconds
                    </option>
                    <option value="120" selected={@room_state.settings.timer_seconds == 120}>
                      2 minutes
                    </option>
                  </select>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Scoring Mode</span>
                  </label>
                  <select
                    class="select select-bordered"
                    name="scoring"
                    disabled={!@is_creator}
                  >
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
            </form>

            <%= if map_size(@players) >= 2 do %>
              <div class="mt-6">
                <button
                  phx-click="vote_start"
                  class={[
                    "btn btn-block",
                    if(@has_voted_start, do: "btn-success", else: "btn-primary")
                  ]}
                  disabled={@has_voted_start}
                >
                  <%= if @has_voted_start do %>
                    <.icon name="hero-check-circle" class="w-5 h-5 mr-2" /> Ready!
                  <% else %>
                    <.icon name="hero-play" class="w-5 h-5 mr-2" /> Ready to Start
                  <% end %>
                </button>
                <%= if @votes_start > 0 do %>
                  <p class="text-center text-sm mt-2 text-base-content/60">
                    {@votes_start}/{@player_count} players ready
                  </p>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
      <%!-- Practice Range --%>
      <div class="card bg-base-200">
        <div class="card-body">
          <div class="flex justify-between items-center mb-4">
            <h2 class="card-title">
              <.icon name="hero-academic-cap" class="w-6 h-6" /> Practice Range
            </h2>
            <button phx-click="reset_practice" class="btn btn-sm btn-ghost">
              <.icon name="hero-arrow-path" class="w-4 h-4 mr-1" /> New Text
            </button>
          </div>
          <%!-- Practice Stats --%>
          <%= if @practice_started_at do %>
            <div class="flex gap-4 mb-4">
              <div class="stat bg-base-300 rounded-lg py-2 px-4 flex-1">
                <div class="stat-title text-xs">WPM</div>
                <div class="stat-value text-2xl">{@practice_wpm}</div>
              </div>
              <div class="stat bg-base-300 rounded-lg py-2 px-4 flex-1">
                <div class="stat-title text-xs">Accuracy</div>
                <div class="stat-value text-2xl">{@practice_accuracy}%</div>
              </div>
              <div class="stat bg-base-300 rounded-lg py-2 px-4 flex-1">
                <div class="stat-title text-xs">Words</div>
                <div class="stat-value text-2xl">{@practice_word_index}</div>
              </div>
            </div>
          <% end %>
          <%!-- Practice Text Display --%>
          <div class="bg-base-300 p-4 rounded-lg mb-4 min-h-[100px]">
            <div class="flex flex-wrap gap-2 font-mono text-lg">
              <%= for {word, idx} <- get_practice_visible_words(@practice_text, @practice_word_index) do %>
                <% {_typed_word, was_correct} =
                  Enum.find(@practice_typed_words, {nil, nil}, fn {w_idx, _} -> w_idx == idx end) %>
                <span class={[
                  "whitespace-nowrap transition-colors",
                  cond do
                    idx < @practice_word_index && was_correct == true ->
                      "text-success font-semibold"

                    idx < @practice_word_index && was_correct == false ->
                      "text-error line-through font-semibold"

                    idx == @practice_word_index ->
                      "border-b-2 border-primary font-bold"

                    true ->
                      "text-base-content/40"
                  end
                ]}>
                  {word}
                </span>
              <% end %>
            </div>
          </div>
          <%!-- Practice Input --%>
          <input
            id="practice-input"
            type="text"
            phx-hook="PracticeInput"
            class="input input-bordered input-lg w-full font-mono text-xl"
            placeholder="Start typing to practice..."
            autocomplete="off"
            autocorrect="off"
            spellcheck="false"
          />
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
        <div class="text-9xl font-bold text-primary mt-8 animate-pulse">
          {@countdown || 3}
        </div>
      </div>
    </div>
    """
  end

  # Game View Component
  defp game_view(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Timer and Stats Bar --%>
      <div class="flex justify-between items-center">
        <div class="stats shadow bg-base-200">
          <div class="stat py-3 px-6">
            <div class="stat-title text-xs">Time Remaining</div>
            <div class={[
              "stat-value text-3xl",
              @time_remaining && @time_remaining <= 10 && "text-error animate-pulse"
            ]}>
              {@time_remaining || @room_state.settings.timer_seconds}s
            </div>
          </div>
        </div>

        <div class="stats shadow bg-base-200">
          <div class="stat py-3 px-4">
            <div class="stat-title text-xs">Correct</div>
            <div class="stat-value text-2xl text-success">
              {Enum.count(@typed_words, fn {_, correct} -> correct end)}
            </div>
          </div>
          <div class="stat py-3 px-4">
            <div class="stat-title text-xs">Errors</div>
            <div class="stat-value text-2xl text-error">
              {Enum.count(@typed_words, fn {_, correct} -> !correct end)}
            </div>
          </div>
        </div>
      </div>

      <%!-- Main Typing Area --%>
      <div class="card bg-base-200 shadow-xl">
        <div class="card-body p-8">
          <%!-- Words Display (2 lines visible, scrolling line-by-line) --%>
          <div class="bg-base-300 p-6 rounded-lg mb-6 overflow-hidden" style="height: 140px;">
            <div class="space-y-3">
              <%= for {line_words, line_num} <- visible_lines(@room_state.current_text, @current_word_index, @typed_words) do %>
                <div class="flex flex-wrap gap-x-3 gap-y-1 font-mono text-2xl">
                  <%= for {word, idx} <- line_words do %>
                    <% {_typed_word, was_correct} =
                      Enum.find(@typed_words, {nil, nil}, fn {w_idx, _} ->
                        w_idx == idx
                      end) %>
                    <% opponent_colors =
                      get_opponent_underlines(idx, @player_progress, @players, @player_id) %>
                    <span
                      class={[
                        "whitespace-nowrap transition-colors relative inline-block",
                        cond do
                          idx < @current_word_index && was_correct == true ->
                            "text-success font-semibold"

                          idx < @current_word_index && was_correct == false ->
                            "text-error line-through font-semibold"

                          idx == @current_word_index ->
                            "border-b-4 border-primary font-bold bg-primary/10 px-1"

                          true ->
                            "text-base-content/40"
                        end
                      ]}
                      style={
                        if opponent_colors != [] do
                          underlines =
                            opponent_colors
                            |> Enum.with_index()
                            |> Enum.map(fn {color, offset} ->
                              y_offset = 2 + offset * 3
                              "0 #{y_offset}px 0 0 #{color}"
                            end)
                            |> Enum.join(", ")

                          "box-shadow: #{underlines}; padding-bottom: #{length(opponent_colors) * 3}px;"
                        else
                          ""
                        end
                      }
                    >
                      {word}
                    </span>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Input Field --%>
          <input
            id="typing-input"
            type="text"
            value={@current_input}
            phx-hook="TypingInput"
            class="input input-bordered input-lg w-full font-mono text-2xl"
            placeholder="Start typing..."
            autocomplete="off"
            autocorrect="off"
            spellcheck="false"
            autofocus
          />
        </div>
      </div>

      <%!-- Opponent Progress Boxes --%>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <%= for {id, player} <- @players, id != @player_id do %>
          <% player_color = get_color_for_player(id, @players, @player_id) %>
          <div class="card bg-base-200 shadow">
            <div class="card-body p-4">
              <div class="flex justify-between items-center mb-2">
                <h4 class="font-semibold" style={"color: #{player_color};"}>
                  {player.nickname}
                </h4>
                <span class="text-sm text-base-content/60">
                  Word {@player_progress[id][:current_word_index] || 0}
                </span>
              </div>
              <%!-- Mini word display for opponent --%>
              <div
                class="bg-base-300 p-3 rounded text-xs font-mono overflow-hidden"
                style="max-height: 60px;"
              >
                <div class="flex flex-wrap gap-1">
                  <%= for {word, idx} <- opponent_visible_words(
                        @room_state.current_text,
                        @player_progress[id][:current_word_index] || 0
                      ) do %>
                    <% opponent_typed_words = @player_progress[id][:typed_words] || [] %>
                    <% {_word_idx, was_correct} =
                      Enum.find(opponent_typed_words, {nil, nil}, fn {w_idx, _} ->
                        w_idx == idx
                      end) %>
                    <span class={[
                      "whitespace-nowrap",
                      cond do
                        idx < (@player_progress[id][:current_word_index] || 0) && was_correct == true ->
                          "text-success font-semibold"

                        idx < (@player_progress[id][:current_word_index] || 0) && was_correct == false ->
                          "text-error line-through"

                        idx == (@player_progress[id][:current_word_index] || 0) ->
                          "border-b-2 border-primary font-bold"

                        true ->
                          "text-base-content/30"
                      end
                    ]}>
                      {word}
                    </span>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        <% end %>
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
                <%= if @room_state.settings.scoring_mode == :wpm_accuracy do %>
                  <th>Score</th>
                <% end %>
                <th>WPM</th>
                <th>Accuracy</th>
                <th>Stats</th>
              </tr>
            </thead>
            <tbody>
              <%= for {result, index} <- Enum.with_index(@results, 1) do %>
                <tr class={if result.player_id == @player_id, do: "bg-primary/10"}>
                  <td>
                    <%= if index == 1 do %>
                      <.icon name="hero-trophy" class="w-6 h-6 text-warning" />
                    <% else %>
                      {index}
                    <% end %>
                  </td>
                  <td class="font-medium">{@players[result.player_id][:nickname] || "Unknown"}</td>
                  <%= if @room_state.settings.scoring_mode == :wpm_accuracy do %>
                    <td class="font-bold text-primary">{result.score}</td>
                  <% end %>
                  <td>{result.wpm}</td>
                  <td>{result.accuracy}%</td>
                  <td class="text-sm">
                    <span class="text-success">{result.correct_words} correct</span>
                    / <span class="text-error">{result.incorrect_words} errors</span>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <%= if @calculating_results do %>
          <div class="flex justify-center items-center mt-6">
            <span class="loading loading-spinner loading-lg text-primary"></span>
            <p class="ml-4 text-lg">Calculating results...</p>
          </div>
        <% else %>
          <div class="card-actions justify-center gap-4 mt-6">
            <div class="flex flex-col items-center">
              <button
                phx-click="vote_play_again"
                class={[
                  "btn",
                  if(@has_voted_play_again, do: "btn-success", else: "btn-primary")
                ]}
                disabled={@has_voted_play_again}
              >
                <%= if @has_voted_play_again do %>
                  <.icon name="hero-check-circle" class="w-5 h-5 mr-2" /> Voted
                <% else %>
                  <.icon name="hero-arrow-path" class="w-5 h-5 mr-2" /> Play Again
                <% end %>
              </button>
              <%= if @votes_play_again > 0 do %>
                <p class="text-sm mt-1 text-base-content/60">
                  {@votes_play_again}/{@player_count}
                </p>
              <% end %>
            </div>

            <div class="flex flex-col items-center">
              <button
                phx-click="vote_back_to_lobby"
                class={[
                  "btn",
                  if(@has_voted_lobby, do: "btn-success", else: "btn-ghost")
                ]}
                disabled={@has_voted_lobby}
              >
                <%= if @has_voted_lobby do %>
                  <.icon name="hero-check-circle" class="w-5 h-5 mr-2" /> Voted
                <% else %>
                  <.icon name="hero-arrow-left" class="w-5 h-5 mr-2" /> Back to Lobby
                <% end %>
              </button>
              <%= if @votes_lobby > 0 do %>
                <p class="text-sm mt-1 text-base-content/60">
                  {@votes_lobby}/{@player_count}
                </p>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("update_settings", params, socket) do
    # Build settings update map from form params
    settings_updates =
      []
      |> maybe_add_setting(params, "language", :language, &String.to_existing_atom/1)
      |> maybe_add_setting(params, "rounds", :total_rounds, &String.to_integer/1)
      |> maybe_add_setting(params, "difficulty", :text_difficulty, &String.to_existing_atom/1)
      |> maybe_add_setting(params, "timer", :timer_seconds, &String.to_integer/1)
      |> maybe_add_setting(params, "scoring", :scoring_mode, &String.to_existing_atom/1)
      |> Enum.into(%{})

    if map_size(settings_updates) > 0 do
      update_room_settings(socket, socket.assigns.player_id, settings_updates)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("vote_start", _params, socket) do
    case Room.vote_start(socket.assigns.code, socket.assigns.player_id) do
      :ok -> {:noreply, assign(socket, has_voted_start: true)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Cannot vote: #{reason}")}
    end
  end

  @impl true
  def handle_event("vote_play_again", _params, socket) do
    case Room.vote_play_again(socket.assigns.code, socket.assigns.player_id) do
      :ok -> {:noreply, assign(socket, has_voted_play_again: true)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Cannot vote: #{reason}")}
    end
  end

  @impl true
  def handle_event("vote_back_to_lobby", _params, socket) do
    case Room.vote_back_to_lobby(socket.assigns.code, socket.assigns.player_id) do
      :ok -> {:noreply, assign(socket, has_voted_lobby: true)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Cannot vote: #{reason}")}
    end
  end

  @impl true
  def handle_event("validate_word", %{"word" => typed_word}, socket) do
    case Room.validate_word(socket.assigns.code, socket.assigns.player_id, typed_word) do
      {:ok, is_correct, new_index} ->
        # Update local state
        typed_words = [
          {socket.assigns.current_word_index, is_correct} | socket.assigns.typed_words
        ]

        socket =
          socket
          |> assign(
            current_word_index: new_index,
            typed_words: typed_words,
            current_input: ""
          )

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, current_input: value)}
  end

  @impl true
  def handle_event("update_practice_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, practice_input: value)}
  end

  @impl true
  def handle_event("practice_validate_word", %{"word" => typed_word}, socket) do
    current_index = socket.assigns.practice_word_index
    correct_word = Enum.at(socket.assigns.practice_text, current_index)
    is_correct = typed_word == correct_word

    # Start timer on first word
    started_at = socket.assigns.practice_started_at || System.monotonic_time(:millisecond)

    # Update typed words
    typed_words = [{current_index, is_correct} | socket.assigns.practice_typed_words]

    # Calculate stats
    correct_count = Enum.count(typed_words, fn {_, correct} -> correct end)
    total_count = length(typed_words)
    accuracy = if total_count > 0, do: round(correct_count / total_count * 100), else: 100

    # Fix WPM calculation: elapsed_time in minutes
    elapsed_milliseconds = System.monotonic_time(:millisecond) - started_at
    elapsed_minutes = elapsed_milliseconds / 60_000
    wpm = if elapsed_minutes > 0, do: round(correct_count / elapsed_minutes), else: 0

    # Check if we need to add more words (make it endless)
    next_index = current_index + 1
    practice_text = socket.assigns.practice_text

    practice_text =
      if next_index >= length(practice_text) - 5 do
        # Add more words when approaching the end (5 words before end)
        practice_text ++ generate_practice_text()
      else
        practice_text
      end

    socket =
      assign(socket,
        practice_input: "",
        practice_word_index: next_index,
        practice_typed_words: typed_words,
        practice_started_at: started_at,
        practice_wpm: wpm,
        practice_accuracy: accuracy,
        practice_text: practice_text
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("reset_practice", _params, socket) do
    {:noreply,
     assign(socket,
       practice_text: generate_practice_text(),
       practice_input: "",
       practice_word_index: 0,
       practice_typed_words: [],
       practice_started_at: nil,
       practice_wpm: 0,
       practice_accuracy: 100
     )}
  end

  # PubSub Message Handlers

  @impl true
  def handle_info(%{event: "presence_diff", payload: %{joins: joins, leaves: leaves}}, socket) do
    # Check if creator needs reassignment when players join or leave
    if map_size(joins) > 0 or map_size(leaves) > 0 do
      Room.check_creator(socket.assigns.code)
    end

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
  def handle_info({:creator_changed, new_creator_id}, socket) do
    is_creator = new_creator_id == socket.assigns.player_id

    socket =
      if is_creator do
        socket
        |> assign(is_creator: true)
        |> put_flash(:info, "You are now the room creator and can change settings")
      else
        assign(socket, is_creator: false)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:game_starting, %{countdown: countdown}}, socket) do
    room_state = Room.get_state(socket.assigns.code)

    {:noreply,
     assign(socket,
       room_state: room_state,
       countdown: countdown,
       # Reset all voting flags when game starts
       has_voted_start: false,
       has_voted_play_again: false,
       has_voted_lobby: false,
       votes_start: 0,
       votes_play_again: 0,
       votes_lobby: 0
     )}
  end

  @impl true
  def handle_info({:countdown_update, count}, socket) do
    {:noreply, assign(socket, countdown: count)}
  end

  @impl true
  def handle_info({:vote_update, type, votes, player_count}, socket) do
    case type do
      :start ->
        {:noreply, assign(socket, votes_start: votes, player_count: player_count)}

      :play_again ->
        {:noreply, assign(socket, votes_play_again: votes, player_count: player_count)}

      :back_to_lobby ->
        {:noreply, assign(socket, votes_lobby: votes, player_count: player_count)}
    end
  end

  @impl true
  def handle_info({:calculating_results, _}, socket) do
    {:noreply, assign(socket, calculating_results: true)}
  end

  @impl true
  def handle_info({:returned_to_lobby, _}, socket) do
    room_state = Room.get_state(socket.assigns.code)

    {:noreply,
     assign(socket,
       room_state: room_state,
       has_voted_lobby: false,
       has_voted_play_again: false,
       votes_lobby: 0,
       votes_play_again: 0
     )}
  end

  @impl true
  def handle_info({:game_started, %{words: words}}, socket) do
    room_state = %{socket.assigns.room_state | status: :playing, current_text: words}

    # Initialize player_progress for all players
    player_progress =
      Enum.into(socket.assigns.players, %{}, fn {player_id, _player} ->
        {player_id, %{current_word_index: 0, typed_words: []}}
      end)

    socket =
      socket
      |> assign(
        room_state: room_state,
        time_remaining: room_state.settings.timer_seconds,
        current_word_index: 0,
        typed_words: [],
        current_input: "",
        player_progress: player_progress,
        # Reset practice mode
        practice_input: "",
        practice_word_index: 0,
        practice_typed_words: [],
        practice_started_at: nil
      )
      |> push_event("game_started", %{})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:timer_update, time_remaining}, socket) do
    {:noreply, assign(socket, time_remaining: time_remaining)}
  end

  @impl true
  def handle_info({:timer_expired, _}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:word_validated, player_id, word_index, is_correct}, socket) do
    # Update opponent progress tracking with correct/incorrect info
    player_progress =
      Map.update(
        socket.assigns.player_progress,
        player_id,
        %{current_word_index: word_index + 1, typed_words: [{word_index, is_correct}]},
        fn progress ->
          %{
            progress
            | current_word_index: word_index + 1,
              typed_words: [{word_index, is_correct} | progress[:typed_words] || []]
          }
        end
      )

    {:noreply, assign(socket, player_progress: player_progress)}
  end

  @impl true
  def handle_info({:results, results}, socket) do
    room_state = %{socket.assigns.room_state | status: :results}

    {:noreply,
     assign(socket,
       room_state: room_state,
       results: results,
       calculating_results: false,
       has_voted_start: false,
       votes_start: 0
     )}
  end

  @impl true
  def handle_info({:game_over, _results}, socket) do
    {:noreply, socket}
  end

  # Private Helpers

  defp update_room_settings(socket, player_id, settings) do
    case Room.update_settings(socket.assigns.code, player_id, settings) do
      {:ok, _} ->
        {:noreply, socket}

      {:error, :not_creator} ->
        {:noreply, put_flash(socket, :error, "Only the room creator can change settings")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot update: #{reason}")}
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

    all_players = Map.merge(socket.assigns.players, new_players)

    assign(socket, players: all_players, player_count: map_size(all_players))
  end

  defp remove_players(socket, leaves) do
    player_ids = Map.keys(leaves)
    remaining_players = Map.drop(socket.assigns.players, player_ids)
    assign(socket, players: remaining_players, player_count: map_size(remaining_players))
  end

  # Calculate which lines to show (2 lines at a time, line-by-line scrolling)
  # Each line has a fixed number of words (adjust based on screen width)
  defp visible_lines(all_words, current_index, _typed_words) when is_list(all_words) do
    words_per_line = 15

    # Calculate which line the current word is on
    current_line = div(current_index, words_per_line)

    # Always show 2 lines: current line and next line
    start_line = current_line
    lines_to_show = 2

    # Get words for these lines
    start_word_index = start_line * words_per_line
    words_to_show = lines_to_show * words_per_line

    all_words
    |> Enum.slice(start_word_index, words_to_show)
    |> Enum.with_index(start_word_index)
    |> Enum.chunk_every(words_per_line)
    |> Enum.with_index(start_line)
  end

  defp visible_lines(_all_words, _current_index, _typed_words), do: []

  # Calculate visible words for opponent mini-display (~25 words)
  defp opponent_visible_words(all_words, opponent_index) when is_list(all_words) do
    words_per_view = 25

    # Center around opponent's current position
    start_index = max(0, opponent_index - 3)

    all_words
    |> Enum.slice(start_index, words_per_view)
    |> Enum.with_index(start_index)
  end

  defp opponent_visible_words(_all_words, _opponent_index), do: []

  # Get underlines for opponents who are currently on this word
  defp get_opponent_underlines(word_index, player_progress, players, current_player_id) do
    players
    |> Enum.reject(fn {id, _} -> id == current_player_id end)
    |> Enum.with_index()
    |> Enum.filter(fn {{opponent_id, _}, _idx} ->
      opponent_current_index = player_progress[opponent_id][:current_word_index] || 0
      opponent_current_index == word_index
    end)
    |> Enum.map(fn {{_id, _player}, idx} -> get_player_color(idx) end)
  end

  # Assign colors to players based on their index
  # Use contrasting colors that work well on both yellow and black backgrounds
  defp get_player_color(index) do
    colors = [
      "rgb(220, 38, 38)",
      # red
      "rgb(37, 99, 235)",
      # blue
      "rgb(22, 163, 74)",
      # green
      "rgb(168, 85, 247)",
      # purple
      "rgb(249, 115, 22)",
      # orange
      "rgb(236, 72, 153)",
      # pink
      "rgb(20, 184, 166)",
      # teal
      "rgb(147, 51, 234)"
      # violet
    ]

    Enum.at(colors, rem(index, length(colors)))
  end

  # Get color for a specific player ID
  defp get_color_for_player(player_id, players, current_player_id) do
    players
    |> Enum.reject(fn {id, _} -> id == current_player_id end)
    |> Enum.with_index()
    |> Enum.find_value(fn {{id, _}, idx} ->
      if id == player_id, do: get_player_color(idx), else: nil
    end) || "rgb(120, 120, 120)"
  end

  defp generate_player_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end

  defp generate_nickname do
    adjectives = ["Swift", "Quick", "Fast", "Rapid", "Speedy", "Lightning", "Turbo", "Blazing"]
    nouns = ["Typer", "Racer", "Champ", "Master", "Ace", "Pro", "Wizard", "Ninja"]

    "#{Enum.random(adjectives)}#{Enum.random(nouns)}"
  end

  defp update_creator_status(socket) do
    room_state = Room.get_state(socket.assigns.code)
    # Handle rooms that don't have creator_id yet (backward compatibility)
    creator_id = Map.get(room_state, :creator_id)
    is_creator = creator_id == socket.assigns.player_id
    assign(socket, is_creator: is_creator)
  end

  defp maybe_add_setting(acc, params, param_key, setting_key, converter) do
    if Map.has_key?(params, param_key) do
      [{setting_key, converter.(params[param_key])} | acc]
    else
      acc
    end
  end

  defp generate_practice_text do
    # Generate a small set of common words for practice
    words = [
      "the",
      "be",
      "to",
      "of",
      "and",
      "a",
      "in",
      "that",
      "have",
      "it",
      "for",
      "not",
      "on",
      "with",
      "he",
      "as",
      "you",
      "do",
      "at",
      "this",
      "but",
      "his",
      "by",
      "from",
      "they",
      "we",
      "say",
      "her",
      "she",
      "or",
      "an",
      "will",
      "my",
      "one",
      "all",
      "would",
      "there",
      "their",
      "what",
      "so",
      "up",
      "out",
      "if",
      "about",
      "who",
      "get",
      "which",
      "go",
      "me"
    ]

    # Return 30 random words
    Enum.take_random(words, 30)
  end

  defp get_practice_visible_words(practice_text, current_index) do
    # Show 40 words: some before current, current, and many after
    start_index = max(0, current_index - 5)
    words_to_show = 40

    practice_text
    |> Enum.slice(start_index, words_to_show)
    |> Enum.with_index(start_index)
  end
end
