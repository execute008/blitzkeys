defmodule BlitzkeysWeb.HomeLive do
  use BlitzkeysWeb, :live_view

  alias Blitzkeys.Rooms.Supervisor, as: RoomsSupervisor

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, join_code: "", join_error: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="w-screen h-90vh flex items-center justify-center px-4 fixed top-10vh left-0">
        <div class="max-w-2xl w-full">
          <%!-- Hero Section --%>
          <div class="text-center mb-12">
            <h1 class="text-6xl font-bold mb-4 bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent">
              BlitzKeys
            </h1>
            <p class="text-xl text-base-content/70">
              Lightning-fast multiplayer typing battles
            </p>
          </div>

          <%!-- Action Cards --%>
          <div class="grid md:grid-cols-2 gap-6">
            <%!-- Create Room Card --%>
            <div class="card bg-base-200 shadow-xl hover:shadow-2xl transition-all">
              <div class="card-body">
                <h2 class="card-title text-2xl mb-2">
                  <.icon name="hero-plus-circle" class="w-8 h-8 text-primary" /> Create Room
                </h2>
                <p class="text-base-content/70 mb-4">
                  Start a new game and invite your friends
                </p>
                <div class="card-actions">
                  <button
                    phx-click="create_room"
                    class="btn btn-primary btn-block"
                  >
                    Create New Room
                  </button>
                </div>
              </div>
            </div>

            <%!-- Join Room Card --%>
            <div class="card bg-base-200 shadow-xl hover:shadow-2xl transition-all">
              <div class="card-body">
                <h2 class="card-title text-2xl mb-2">
                  <.icon name="hero-arrow-right-circle" class="w-8 h-8 text-secondary" /> Join Room
                </h2>
                <p class="text-base-content/70 mb-4">
                  Enter a room code to join a game
                </p>
                <form phx-submit="join_room" id="join-room-form">
                  <input
                    type="text"
                    name="code"
                    placeholder="Enter room code"
                    value={@join_code}
                    phx-change="update_join_code"
                    class="input input-bordered w-full mb-3"
                    autocomplete="off"
                  />
                  <%= if @join_error do %>
                    <p class="text-error text-sm mb-3">{@join_error}</p>
                  <% end %>
                  <button
                    type="submit"
                    class="btn btn-secondary btn-block"
                    disabled={@join_code == ""}
                  >
                    Join Room
                  </button>
                </form>
              </div>
            </div>
          </div>

          <%!-- Browse Public Rooms --%>
          <div class="mt-12">
            <.link
              navigate={~p"/rooms"}
              class="card bg-gradient-to-r from-primary to-secondary hover:shadow-2xl transition-all cursor-pointer"
            >
              <div class="card-body text-center">
                <h2 class="card-title text-2xl justify-center text-white">
                  <.icon name="hero-users" class="w-8 h-8" /> Browse Public Rooms
                </h2>
                <p class="text-white/90">
                  Join an existing game and compete with other players
                </p>
              </div>
            </.link>
          </div>

          <%!-- Features --%>
          <div class="mt-16 grid grid-cols-1 md:grid-cols-3 gap-6 text-center">
            <div>
              <.icon name="hero-bolt" class="w-12 h-12 mx-auto mb-3 text-primary" />
              <h3 class="font-semibold mb-2">Real-time Racing</h3>
              <p class="text-sm text-base-content/60">
                See your opponents' progress live
              </p>
            </div>
            <div>
              <.icon name="hero-globe-alt" class="w-12 h-12 mx-auto mb-3 text-secondary" />
              <h3 class="font-semibold mb-2">Multiple Languages</h3>
              <p class="text-sm text-base-content/60">
                Practice in English, Spanish, German & more
              </p>
            </div>
            <div>
              <.icon name="hero-trophy" class="w-12 h-12 mx-auto mb-3 text-accent" />
              <h3 class="font-semibold mb-2">Custom Scoring</h3>
              <p class="text-sm text-base-content/60">
                WPM, accuracy, or best-of-X rounds
              </p>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("create_room", _params, socket) do
    code = generate_room_code()

    case RoomsSupervisor.create_room(code) do
      {:ok, _pid} ->
        {:noreply, push_navigate(socket, to: ~p"/room/#{code}")}

      {:error, {:already_started, _pid}} ->
        # Code collision (very rare), try again
        handle_event("create_room", %{}, socket)

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create room: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("update_join_code", %{"code" => code}, socket) do
    {:noreply, assign(socket, join_code: String.upcase(code), join_error: nil)}
  end

  @impl true
  def handle_event("join_room", _params, socket) do
    code = socket.assigns.join_code

    case Blitzkeys.Rooms.Room.whereis(code) do
      nil ->
        {:noreply, assign(socket, join_error: "Room not found")}

      _pid ->
        {:noreply, push_navigate(socket, to: ~p"/room/#{code}")}
    end
  end

  # Private helpers

  defp generate_room_code do
    :crypto.strong_rand_bytes(3)
    |> Base.encode16()
  end
end
