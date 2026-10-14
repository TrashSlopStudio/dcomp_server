defmodule DcompWeb.GameComponents do
  @moduledoc "Small pieces shared by the game pages, plus the number/time formatting they use."
  use DcompWeb, :html

  ## Components

  attr :login, :string, default: nil, doc: "GitHub login; nil renders the anonymous icon"
  attr :url, :string, default: nil
  attr :size, :string, default: "size-6"
  attr :link, :boolean, default: true

  def avatar(%{login: nil} = assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center justify-center rounded-full bg-base-300 text-base-content/50",
        @size
      ]}
      title="Unknown contributor"
    >
      <.icon name="hero-user-solid" class="size-3/5" />
    </span>
    """
  end

  def avatar(assigns) do
    ~H"""
    <img
      src={@url || Dcomp.Decomp.Contributor.avatar_url_for(@login)}
      alt=""
      loading="lazy"
      class={["rounded-full bg-base-300 object-cover", @size]}
    />
    """
  end

  @doc "Avatar plus login, linking to the GitHub profile (or 'Unknown' when anonymous)."
  attr :login, :string, default: nil
  attr :url, :string, default: nil
  attr :size, :string, default: "size-6"

  def person(%{login: nil} = assigns) do
    ~H"""
    <span class="inline-flex items-center gap-2 text-base-content/60">
      <.avatar size={@size} /> Unknown
    </span>
    """
  end

  def person(assigns) do
    ~H"""
    <a
      href={"https://github.com/#{@login}"}
      target="_blank"
      rel="noopener noreferrer"
      class="inline-flex items-center gap-2 transition hover:text-primary"
    >
      <.avatar login={@login} url={@url} size={@size} />
      <span class="truncate">{@login}</span>
    </a>
    """
  end

  attr :value, :float, required: true, doc: "0..100"
  attr :class, :string, default: nil

  def progress_bar(assigns) do
    ~H"""
    <div
      class={["h-2 w-full overflow-hidden rounded-full bg-base-300", @class]}
      role="progressbar"
      aria-valuenow={@value}
      aria-valuemin="0"
      aria-valuemax="100"
    >
      <div
        class="h-full rounded-full bg-primary transition-[width] duration-700"
        style={"width: #{@value}%"}
      />
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :sub, :string, default: nil
  attr :icon, :string, default: nil

  def stat(assigns) do
    ~H"""
    <div id={@id} class="rounded-2xl border border-base-300 bg-base-200/50 p-4">
      <div class="flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-base-content/60">
        <.icon :if={@icon} name={@icon} class="size-4" />
        {@label}
      </div>
      <div class="mt-1 text-2xl font-semibold tracking-tight">{@value}</div>
      <div :if={@sub} class="mt-0.5 text-xs text-base-content/60">{@sub}</div>
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true
  slot :aside

  def panel(assigns) do
    ~H"""
    <section id={@id} class={["rounded-2xl border border-base-300 bg-base-200/50 p-5", @class]}>
      <div class="mb-3 flex items-center justify-between gap-2">
        <h2 class="text-sm font-semibold tracking-wide">{@title}</h2>
        {render_slot(@aside)}
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :active, :atom, required: true, values: [:games, :settings, :users]

  def admin_tabs(assigns) do
    ~H"""
    <nav
      id="admin-tabs"
      class="flex gap-1 rounded-xl border border-base-300 bg-base-200/50 p-1 text-sm"
    >
      <.link
        :for={
          {key, label, path} <- [
            {:games, "Games", ~p"/admin/games"},
            {:settings, "Settings", ~p"/admin/settings"},
            {:users, "Users", ~p"/admin/users"}
          ]
        }
        id={"admin-tab-#{key}"}
        navigate={path}
        class={[
          "flex-1 rounded-lg px-4 py-2 text-center font-medium transition",
          if(@active == key,
            do: "bg-base-100 shadow",
            else: "text-base-content/60 hover:text-base-content"
          )
        ]}
      >
        {label}
      </.link>
    </nav>
    """
  end

  ## Formatting

  def image_url(%{image_path: nil}), do: nil
  def image_url(%{image_path: name}), do: "/uploads/" <> name

  def number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  def number(n) when is_float(n), do: n |> round() |> number()
  def number(nil), do: "–"

  def bytes(n) when n >= 1_048_576, do: "#{Float.round(n / 1_048_576, 1)} MiB"
  def bytes(n) when n >= 1024, do: "#{Float.round(n / 1024, 1)} KiB"
  def bytes(n), do: "#{n} B"

  def percent(p), do: "#{:erlang.float_to_binary(p * 1.0, decimals: 1)}%"

  def duration(nil), do: "–"
  def duration(s) when s < 3600, do: "#{max(round(s / 60), 1)} min"
  def duration(s) when s < 172_800, do: "#{Float.round(s / 3600, 1)} h"
  def duration(s), do: "#{Float.round(s / 86_400, 1)} days"

  def eta(nil), do: "–"
  def eta(days) when days < 1, do: "< 1 day"
  def eta(days) when days < 120, do: "#{round(days)} days"
  def eta(days), do: "#{Float.round(days / 30, 1)} months"

  @doc "Coarse relative time (`5 min ago`); the page re-renders on every sync."
  def time_ago(nil, _now), do: "never"

  def time_ago(%DateTime{} = at, now) do
    s = DateTime.diff(now, at)

    cond do
      s < 60 -> "just now"
      s < 3600 -> "#{div(s, 60)} min ago"
      s < 86_400 -> "#{div(s, 3600)} h ago"
      true -> "#{div(s, 86_400)} days ago"
    end
  end

  def time_left(nil, _now), do: "–"

  def time_left(%DateTime{} = at, now) do
    case DateTime.diff(at, now) do
      s when s <= 0 -> "expired"
      s when s < 3600 -> "#{div(s, 60)} min left"
      s -> "#{div(s, 3600)} h left"
    end
  end

  def event_label(:claim), do: "claimed"
  def event_label(:solve), do: "solved"
  def event_label(:release), do: "released"
  def event_label(:expire), do: "claim expired"

  def event_icon(:claim), do: "hero-hand-raised"
  def event_icon(:solve), do: "hero-check-circle"
  def event_icon(:release), do: "hero-arrow-uturn-left"
  def event_icon(:expire), do: "hero-clock"
end
