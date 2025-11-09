defmodule BlitzkeysWeb.PublicRoomsLive do
  use BlitzkeysWeb, :live_view

  alias Blitzkeys.Rooms.Supervisor, as: RoomsSupervisor

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Blitzkeys.PubSub, "lobby")
      # Refresh rooms list every 5 seconds
      :timer.send_interval(5000, self(), :refresh_rooms)
    end

    rooms = RoomsSupervisor.list_rooms_with_info()

    socket =
      socket
      |> stream(:rooms, rooms, reset: true)
      |> assign(:rooms_empty?, rooms == [])

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="w-screen min-h-90vh px-4 py-8 fixed top-10vh left-0 overflow-y-auto">
        <div class="max-w-4xl mx-auto">
          <%!-- Header --%>
          <div class="text-center mb-8">
            <h1 class="text-4xl font-bold mb-2">
              <.icon name="hero-users" class="w-10 h-10 inline-block mr-2 text-primary" />
              Public Rooms
            </h1>
            <p class="text-base-content/70">
              Join an active room or
              <.link navigate={~p"/"} class="link link-primary">create your own</.link>
            </p>
          </div>

          <%!-- Rooms List --%>
          <div id="public-rooms" phx-update="stream" class="space-y-3">
            <div class="hidden only:block text-center py-12 text-base-content/60">
              <.icon name="hero-inbox" class="w-16 h-16 mx-auto mb-4 opacity-50" />
              <p class="text-xl mb-2">No public rooms available</p>
              <p class="text-sm">Be the first to create one!</p>
              <.link navigate={~p"/"} class="btn btn-primary mt-4">
                Create Room
              </.link>
            </div>

            <div
              :for={{id, room} <- @streams.rooms}
              id={id}
              class="card bg-base-200 hover:bg-base-300 hover:shadow-lg transition-all cursor-pointer"
              phx-click="join_room"
              phx-value-code={room.code}
            >
              <div class="card-body py-4 px-6">
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-4">
                    <div class="font-mono text-2xl font-bold text-primary">
                      {room.code}
                    </div>
                    <div class={[
                      "badge badge-sm",
                      room.status == :lobby && "badge-success",
                      room.status == :countdown && "badge-warning",
                      room.status == :playing && "badge-error",
                      room.status == :results && "badge-info"
                    ]}>
                      {format_status(room.status)}
                    </div>
                  </div>

                  <div class="flex items-center gap-2">
                    <.icon name="hero-users" class="w-5 h-5 text-base-content/60" />
                    <span class="text-sm text-base-content/80">
                      {room.player_count} {if room.player_count == 1, do: "player", else: "players"}
                    </span>
                    <.icon name="hero-arrow-right" class="w-5 h-5 text-primary ml-2" />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("join_room", %{"code" => code}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/room/#{code}")}
  end

  @impl true
  def handle_info(:refresh_rooms, socket) do
    rooms = RoomsSupervisor.list_rooms_with_info()

    socket =
      socket
      |> stream(:rooms, rooms, reset: true)
      |> assign(:rooms_empty?, rooms == [])

    {:noreply, socket}
  end

  @impl true
  def handle_info({:room_created, _code}, socket) do
    send(self(), :refresh_rooms)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:room_updated, _code}, socket) do
    send(self(), :refresh_rooms)
    {:noreply, socket}
  end

  # Private helpers

  defp format_status(:lobby), do: "Lobby"
  defp format_status(:countdown), do: "Starting"
  defp format_status(:playing), do: "In Game"
  defp format_status(:results), do: "Results"
  defp format_status(_), do: "Unknown"
end
