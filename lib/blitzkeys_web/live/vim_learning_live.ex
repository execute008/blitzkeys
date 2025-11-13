defmodule BlitzkeysWeb.VimLearningLive do
  use BlitzkeysWeb, :live_view
  alias BlitzkeysWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       selected_category: "basic_movement",
       completed_lessons: MapSet.new(),
       current_lesson: nil,
       show_lesson_detail: false,
       categories: get_categories(),
       lessons: get_all_lessons()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-6xl mx-auto px-4 py-8">
        <!-- Header -->
        <div class="text-center mb-12">
          <h1 class="text-5xl font-bold mb-4 bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent">
            Master Vim & Neovim
          </h1>
          <p class="text-xl text-base-content/70 max-w-2xl mx-auto">
            Learn to move at lightning speed with comprehensive lessons covering basic to advanced Vim movements
          </p>
        </div>

        <!-- Progress Stats -->
        <div class="stats shadow w-full mb-8">
          <div class="stat">
            <div class="stat-figure text-primary">
              <.icon name="hero-academic-cap" class="w-8 h-8" />
            </div>
            <div class="stat-title">Total Lessons</div>
            <div class="stat-value text-primary"><%= length(@lessons) %></div>
            <div class="stat-desc">Across all categories</div>
          </div>

          <div class="stat">
            <div class="stat-figure text-secondary">
              <.icon name="hero-check-circle" class="w-8 h-8" />
            </div>
            <div class="stat-title">Completed</div>
            <div class="stat-value text-secondary"><%= MapSet.size(@completed_lessons) %></div>
            <div class="stat-desc">
              <%= trunc(MapSet.size(@completed_lessons) / length(@lessons) * 100) %>% progress
            </div>
          </div>

          <div class="stat">
            <div class="stat-figure text-accent">
              <.icon name="hero-bolt" class="w-8 h-8" />
            </div>
            <div class="stat-title">Current Category</div>
            <div class="stat-value text-accent text-2xl">
              <%= @categories[@selected_category].name %>
            </div>
            <div class="stat-desc">Keep learning!</div>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-4 gap-6">
          <!-- Category Sidebar -->
          <div class="lg:col-span-1">
            <div class="card bg-base-200 shadow-xl sticky top-4">
              <div class="card-body p-4">
                <h2 class="card-title text-lg mb-4">Categories</h2>
                <ul class="menu menu-compact p-0">
                  <%= for {key, category} <- @categories do %>
                    <li>
                      <button
                        phx-click="select_category"
                        phx-value-category={key}
                        class={[
                          "flex items-center justify-between",
                          @selected_category == key && "active"
                        ]}
                      >
                        <span class="flex items-center gap-2">
                          <.icon name={category.icon} class="w-4 h-4" />
                          <%= category.name %>
                        </span>
                        <span class="badge badge-sm">
                          <%= count_lessons_in_category(@lessons, key) %>
                        </span>
                      </button>
                    </li>
                  <% end %>
                </ul>
              </div>
            </div>
          </div>

          <!-- Lessons Grid -->
          <div class="lg:col-span-3">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <%= for lesson <- filter_lessons_by_category(@lessons, @selected_category) do %>
                <div class="card bg-base-100 shadow-lg hover:shadow-2xl transition-all border-2 border-base-300">
                  <div class="card-body p-6">
                    <div class="flex items-start justify-between mb-3">
                      <h3 class="card-title text-lg flex items-center gap-2">
                        <%= if MapSet.member?(@completed_lessons, lesson.id) do %>
                          <.icon name="hero-check-circle-solid" class="w-5 h-5 text-success" />
                        <% else %>
                          <.icon name="hero-circle-stack" class="w-5 h-5 text-base-content/40" />
                        <% end %>
                        <%= lesson.title %>
                      </h3>
                      <div class="badge badge-sm badge-primary"><%= lesson.difficulty %></div>
                    </div>

                    <p class="text-sm text-base-content/70 mb-4"><%= lesson.description %></p>

                    <div class="space-y-2 mb-4">
                      <%= for {command, desc} <- Enum.take(lesson.commands, 3) do %>
                        <div class="flex items-center gap-2 text-sm">
                          <kbd class="kbd kbd-sm"><%= command %></kbd>
                          <span class="text-base-content/60"><%= desc %></span>
                        </div>
                      <% end %>
                      <%= if length(lesson.commands) > 3 do %>
                        <p class="text-xs text-primary">
                          + <%= length(lesson.commands) - 3 %> more commands...
                        </p>
                      <% end %>
                    </div>

                    <div class="card-actions justify-end">
                      <button
                        phx-click="view_lesson"
                        phx-value-lesson-id={lesson.id}
                        class="btn btn-primary btn-sm"
                      >
                        <%= if MapSet.member?(@completed_lessons, lesson.id), do: "Review", else: "Learn" %>
                        <.icon name="hero-arrow-right" class="w-4 h-4" />
                      </button>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Lesson Detail Modal -->
        <%= if @show_lesson_detail && @current_lesson do %>
          <div
            class="modal modal-open"
            phx-click="close_lesson"
            phx-window-keydown="close_lesson"
            phx-key="Escape"
          >
            <div class="modal-box max-w-4xl" phx-click="stop_propagation">
              <div class="flex items-start justify-between mb-6">
                <div>
                  <h3 class="font-bold text-3xl mb-2"><%= @current_lesson.title %></h3>
                  <div class="flex gap-2">
                    <div class="badge badge-primary"><%= @current_lesson.difficulty %></div>
                    <div class="badge badge-outline"><%= @current_lesson.category %></div>
                  </div>
                </div>
                <button phx-click="close_lesson" class="btn btn-sm btn-circle btn-ghost">✕</button>
              </div>

              <p class="text-base-content/80 mb-6"><%= @current_lesson.description %></p>

              <div class="divider">Commands</div>

              <div class="space-y-6">
                <%= for {command, description} <- @current_lesson.commands do %>
                  <div class="card bg-base-200">
                    <div class="card-body p-4">
                      <div class="flex items-center gap-4">
                        <kbd class="kbd kbd-lg font-mono text-lg min-w-24 justify-center">
                          <%= command %>
                        </kbd>
                        <div class="flex-1">
                          <p class="text-base-content"><%= description %></p>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>

              <%= if @current_lesson.tips do %>
                <div class="alert alert-info mt-6">
                  <.icon name="hero-light-bulb" class="w-5 h-5" />
                  <div>
                    <h4 class="font-bold">Pro Tips</h4>
                    <ul class="list-disc list-inside text-sm mt-2">
                      <%= for tip <- @current_lesson.tips do %>
                        <li><%= tip %></li>
                      <% end %>
                    </ul>
                  </div>
                </div>
              <% end %>

              <div class="modal-action">
                <button
                  phx-click="toggle_completion"
                  phx-value-lesson-id={@current_lesson.id}
                  class={[
                    "btn",
                    if(MapSet.member?(@completed_lessons, @current_lesson.id),
                      do: "btn-outline",
                      else: "btn-success"
                    )
                  ]}
                >
                  <%= if MapSet.member?(@completed_lessons, @current_lesson.id) do %>
                    <.icon name="hero-arrow-path" class="w-5 h-5" />
                    Mark as Incomplete
                  <% else %>
                    <.icon name="hero-check-circle" class="w-5 h-5" />
                    Mark as Complete
                  <% end %>
                </button>
                <button phx-click="close_lesson" class="btn">Close</button>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("select_category", %{"category" => category}, socket) do
    {:noreply, assign(socket, selected_category: category)}
  end

  @impl true
  def handle_event("view_lesson", %{"lesson-id" => lesson_id}, socket) do
    lesson = Enum.find(socket.assigns.lessons, &(&1.id == lesson_id))

    {:noreply,
     assign(socket,
       current_lesson: lesson,
       show_lesson_detail: true
     )}
  end

  @impl true
  def handle_event("close_lesson", _params, socket) do
    {:noreply, assign(socket, show_lesson_detail: false)}
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_completion", %{"lesson-id" => lesson_id}, socket) do
    completed_lessons =
      if MapSet.member?(socket.assigns.completed_lessons, lesson_id) do
        MapSet.delete(socket.assigns.completed_lessons, lesson_id)
      else
        MapSet.put(socket.assigns.completed_lessons, lesson_id)
      end

    {:noreply, assign(socket, completed_lessons: completed_lessons)}
  end

  # Private helper functions

  defp get_categories do
    %{
      "basic_movement" => %{
        name: "Basic Movement",
        icon: "hero-arrow-right-circle"
      },
      "word_movement" => %{
        name: "Word Movement",
        icon: "hero-forward"
      },
      "line_movement" => %{
        name: "Line Movement",
        icon: "hero-arrows-right-left"
      },
      "screen_movement" => %{
        name: "Screen Movement",
        icon: "hero-arrows-up-down"
      },
      "search_navigation" => %{
        name: "Search & Navigate",
        icon: "hero-magnifying-glass"
      },
      "text_objects" => %{
        name: "Text Objects",
        icon: "hero-cube"
      },
      "marks_jumps" => %{
        name: "Marks & Jumps",
        icon: "hero-bookmark"
      },
      "advanced" => %{
        name: "Advanced",
        icon: "hero-rocket-launch"
      }
    }
  end

  defp get_all_lessons do
    [
      # Basic Movement
      %{
        id: "basic-hjkl",
        category: "basic_movement",
        difficulty: "Beginner",
        title: "The Holy HJKL",
        description: "Master the fundamental navigation keys that form the foundation of Vim movement.",
        commands: [
          {"h", "Move left (one character)"},
          {"j", "Move down (one line)"},
          {"k", "Move up (one line)"},
          {"l", "Move right (one character)"}
        ],
        tips: [
          "Keep your fingers on the home row for maximum efficiency",
          "Practice without arrow keys to build muscle memory",
          "Combine with counts like '5j' to move 5 lines down"
        ]
      },
      %{
        id: "basic-insert",
        category: "basic_movement",
        difficulty: "Beginner",
        title: "Insert Mode Entries",
        description: "Learn different ways to enter insert mode for various editing scenarios.",
        commands: [
          {"i", "Insert before cursor"},
          {"a", "Insert after cursor"},
          {"I", "Insert at beginning of line"},
          {"A", "Insert at end of line"},
          {"o", "Open new line below"},
          {"O", "Open new line above"}
        ],
        tips: [
          "Use 'A' for quick end-of-line editing",
          "'o' and 'O' automatically indent in most configurations",
          "Master these to minimize hand movement"
        ]
      },
      # Word Movement
      %{
        id: "word-basic",
        category: "word_movement",
        difficulty: "Beginner",
        title: "Word Navigation",
        description: "Move efficiently through words and WORDS for faster code traversal.",
        commands: [
          {"w", "Move to start of next word"},
          {"W", "Move to start of next WORD (whitespace-separated)"},
          {"b", "Move to start of previous word"},
          {"B", "Move to start of previous WORD"},
          {"e", "Move to end of current/next word"},
          {"E", "Move to end of current/next WORD"}
        ],
        tips: [
          "Use 'w' for camelCase and 'W' for full identifiers",
          "Combine with counts: '3w' to jump 3 words forward",
          "'e' is great for appending to words with 'ea'"
        ]
      },
      %{
        id: "word-find",
        category: "word_movement",
        difficulty: "Intermediate",
        title: "Find Character",
        description: "Jump to specific characters on the current line with surgical precision.",
        commands: [
          {"f{char}", "Find next occurrence of {char} on line"},
          {"F{char}", "Find previous occurrence of {char} on line"},
          {"t{char}", "Move until (before) next {char}"},
          {"T{char}", "Move until (after) previous {char}"},
          {";", "Repeat last f/F/t/T motion"},
          {",", "Repeat last f/F/t/T motion in opposite direction"}
        ],
        tips: [
          "Use ';' to quickly navigate through repeated characters",
          "'t' is perfect for 'dt{char}' to delete up to a character",
          "Combine with operators: 'cf)' to change up to closing paren"
        ]
      },
      # Line Movement
      %{
        id: "line-within",
        category: "line_movement",
        difficulty: "Beginner",
        title: "Within Line Movement",
        description: "Navigate quickly to important positions within a single line.",
        commands: [
          {"0", "Move to start of line (column 0)"},
          {"^", "Move to first non-blank character"},
          {"$", "Move to end of line"},
          {"g_", "Move to last non-blank character"},
          {"|", "Move to column specified by count"}
        ],
        tips: [
          "Use '^' instead of '0' for code to skip indentation",
          "'$' is commonly used with 'd$' or 'C' to delete to end",
          "'80|' jumps to column 80 (useful for line length checks)"
        ]
      },
      %{
        id: "line-paragraph",
        category: "line_movement",
        difficulty: "Intermediate",
        title: "Paragraph & Block Movement",
        description: "Move through code blocks and paragraphs with ease.",
        commands: [
          {"{", "Move to previous paragraph/block"},
          {"}", "Move to next paragraph/block"},
          {"(", "Move to previous sentence"},
          {")", "Move to next sentence"}
        ],
        tips: [
          "In code, '{' and '}' move between blank-line-separated blocks",
          "Great for navigating between functions",
          "Use 'd{' to delete to previous paragraph"
        ]
      },
      # Screen Movement
      %{
        id: "screen-basic",
        category: "screen_movement",
        difficulty: "Beginner",
        title: "Screen Position",
        description: "Control where the cursor appears on your screen for optimal visibility.",
        commands: [
          {"H", "Move to top of screen (High)"},
          {"M", "Move to middle of screen (Middle)"},
          {"L", "Move to bottom of screen (Low)"},
          {"zt", "Scroll line to top of screen"},
          {"zz", "Scroll line to center of screen"},
          {"zb", "Scroll line to bottom of screen"}
        ],
        tips: [
          "Use 'zz' to center important code you're working on",
          "'H' and 'L' with counts: '10H' moves 10 lines from top",
          "Great for quickly scanning through files"
        ]
      },
      %{
        id: "screen-scroll",
        category: "screen_movement",
        difficulty: "Beginner",
        title: "Scrolling",
        description: "Scroll through your code efficiently without losing your place.",
        commands: [
          {"Ctrl-f", "Scroll forward one page"},
          {"Ctrl-b", "Scroll backward one page"},
          {"Ctrl-d", "Scroll down half page"},
          {"Ctrl-u", "Scroll up half page"},
          {"Ctrl-e", "Scroll down one line"},
          {"Ctrl-y", "Scroll up one line"}
        ],
        tips: [
          "Ctrl-d and Ctrl-u are most commonly used for quick scrolling",
          "Combine with 'zz' to center after jumping",
          "Ctrl-e and Ctrl-y are great for small adjustments"
        ]
      },
      # Search & Navigation
      %{
        id: "search-basic",
        category: "search_navigation",
        difficulty: "Beginner",
        title: "Basic Search",
        description: "Find text anywhere in your file with powerful search commands.",
        commands: [
          {"/pattern", "Search forward for pattern"},
          {"?pattern", "Search backward for pattern"},
          {"n", "Repeat search in same direction"},
          {"N", "Repeat search in opposite direction"},
          {"*", "Search forward for word under cursor"},
          {"#", "Search backward for word under cursor"}
        ],
        tips: [
          "Use '*' to quickly find all occurrences of a variable",
          "Press 'n' repeatedly to cycle through matches",
          "Combine with ':noh' to clear search highlighting"
        ]
      },
      %{
        id: "search-file",
        category: "search_navigation",
        difficulty: "Intermediate",
        title: "File Navigation",
        description: "Jump to specific locations in your file instantly.",
        commands: [
          {"gg", "Go to first line"},
          {"G", "Go to last line"},
          {"{number}G", "Go to line {number}"},
          {"{number}gg", "Go to line {number}"},
          {"%", "Jump to matching bracket/paren/brace"}
        ],
        tips: [
          "Use '50G' or ':50' to jump to line 50",
          "'%' is essential for navigating nested code blocks",
          "Press 'G' to quickly jump to end of file"
        ]
      },
      # Text Objects
      %{
        id: "textobj-word",
        category: "text_objects",
        difficulty: "Intermediate",
        title: "Word Text Objects",
        description: "Operate on entire words with surgical precision using text objects.",
        commands: [
          {"iw", "Inner word (word under cursor)"},
          {"aw", "A word (word + surrounding space)"},
          {"iW", "Inner WORD (whitespace-separated)"},
          {"aW", "A WORD (WORD + surrounding space)"}
        ],
        tips: [
          "Use 'ciw' to change a word from anywhere in it",
          "'daw' deletes word and trailing space",
          "Combine with visual mode: 'viw' to select word"
        ]
      },
      %{
        id: "textobj-delimiters",
        category: "text_objects",
        difficulty: "Intermediate",
        title: "Delimiter Text Objects",
        description: "Work with content inside quotes, parentheses, brackets, and braces.",
        commands: [
          {"i(", "Inner parentheses"},
          {"a(", "A parentheses (includes parens)"},
          {"i{", "Inner braces"},
          {"a{", "A braces (includes braces)"},
          {"i[", "Inner brackets"},
          {"a[", "A brackets (includes brackets)"},
          {"i\"", "Inner double quotes"},
          {"a\"", "A double quotes (includes quotes)"},
          {"i'", "Inner single quotes"},
          {"a'", "A single quotes (includes quotes)"}
        ],
        tips: [
          "Use 'ci\"' to change string contents",
          "'da{' deletes entire code block with braces",
          "Works from anywhere inside the delimiters"
        ]
      },
      %{
        id: "textobj-advanced",
        category: "text_objects",
        difficulty: "Advanced",
        title: "Advanced Text Objects",
        description: "Master complex text objects for powerful editing operations.",
        commands: [
          {"it", "Inner tag (XML/HTML)"},
          {"at", "A tag (includes tags)"},
          {"is", "Inner sentence"},
          {"as", "A sentence"},
          {"ip", "Inner paragraph"},
          {"ap", "A paragraph"}
        ],
        tips: [
          "'dit' deletes HTML tag contents",
          "'dap' deletes entire paragraph",
          "Works great with visual mode for precise selections"
        ]
      },
      # Marks & Jumps
      %{
        id: "marks-basic",
        category: "marks_jumps",
        difficulty: "Intermediate",
        title: "Marks",
        description: "Set bookmarks in your code to jump back to important locations.",
        commands: [
          {"m{a-z}", "Set mark {a-z} in current buffer"},
          {"m{A-Z}", "Set global mark {A-Z} (across files)"},
          {"'{mark}", "Jump to line of mark"},
          {"`{mark}", "Jump to exact position of mark"},
          {":marks", "List all marks"}
        ],
        tips: [
          "Use lowercase marks for within-file bookmarks",
          "Uppercase marks work across different files",
          "'`a' is more precise than \"a for jumping"
        ]
      },
      %{
        id: "marks-jumps",
        category: "marks_jumps",
        difficulty: "Intermediate",
        title: "Jump List",
        description: "Navigate through your jump history like a web browser.",
        commands: [
          {"Ctrl-o", "Jump to previous location in jump list"},
          {"Ctrl-i", "Jump to next location in jump list"},
          {"''", "Jump back to previous position"},
          {"``", "Jump to exact previous position"},
          {":jumps", "Show jump list"}
        ],
        tips: [
          "Think of Ctrl-o/Ctrl-i like browser back/forward",
          "Great for exploring unfamiliar code",
          "Jump list persists across editing sessions"
        ]
      },
      # Advanced
      %{
        id: "advanced-macros",
        category: "advanced",
        difficulty: "Advanced",
        title: "Macros",
        description: "Record and replay complex editing sequences for ultimate productivity.",
        commands: [
          {"q{a-z}", "Start recording macro to register {a-z}"},
          {"q", "Stop recording macro"},
          {"@{a-z}", "Execute macro from register {a-z}"},
          {"@@", "Repeat last executed macro"},
          {"{number}@{a-z}", "Execute macro {number} times"}
        ],
        tips: [
          "Use 'q' to start/stop recording",
          "Test your macro on one line before running on many",
          "Use '100@a' to run macro 100 times"
        ]
      },
      %{
        id: "advanced-registers",
        category: "advanced",
        difficulty: "Advanced",
        title: "Registers",
        description: "Master Vim's clipboard system for advanced copy/paste operations.",
        commands: [
          {"\"{a-z}y", "Yank into register {a-z}"},
          {"\"{a-z}p", "Paste from register {a-z}"},
          {":reg", "Show all registers"},
          {"\"0p", "Paste from yank register (not delete)"},
          {"\"+y", "Yank to system clipboard"},
          {"\"+p", "Paste from system clipboard"}
        ],
        tips: [
          "Use '\"0p' to paste last yanked text after deleting",
          "'\"+ is system clipboard, '\"* is selection",
          "Named registers persist across sessions"
        ]
      },
      %{
        id: "advanced-visual",
        category: "advanced",
        difficulty: "Advanced",
        title: "Visual Block Mode",
        description: "Edit multiple lines simultaneously with visual block mode.",
        commands: [
          {"Ctrl-v", "Enter visual block mode"},
          {"I", "Insert on multiple lines"},
          {"A", "Append on multiple lines"},
          {"c", "Change selected block"},
          {"r", "Replace all characters in block"},
          {"o", "Toggle corner of selection"}
        ],
        tips: [
          "Select block, press 'I', type, then ESC to apply to all lines",
          "Great for commenting multiple lines",
          "Use 'o' to adjust selection from different corners"
        ]
      },
      %{
        id: "advanced-substitute",
        category: "advanced",
        difficulty: "Advanced",
        title: "Search & Replace",
        description: "Powerful find and replace operations across your entire file.",
        commands: [
          {":s/old/new/", "Replace first occurrence on line"},
          {":s/old/new/g", "Replace all occurrences on line"},
          {":%s/old/new/g", "Replace all occurrences in file"},
          {":%s/old/new/gc", "Replace with confirmation"},
          {":'<,'>s/old/new/g", "Replace in visual selection"}
        ],
        tips: [
          "Always use 'c' flag first to confirm replacements",
          "Use '\\<' and '\\>' for whole word matching",
          "Combine with regex for powerful transformations"
        ]
      }
    ]
  end

  defp filter_lessons_by_category(lessons, category) do
    Enum.filter(lessons, &(&1.category == category))
  end

  defp count_lessons_in_category(lessons, category) do
    lessons
    |> filter_lessons_by_category(category)
    |> length()
  end
end
