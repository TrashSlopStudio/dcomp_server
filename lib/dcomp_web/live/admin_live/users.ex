defmodule DcompWeb.AdminLive.Users do
  @moduledoc "Admin: who has an account and who is an admin."
  use DcompWeb, :live_view

  import DcompWeb.GameComponents

  alias Dcomp.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Users · Admin") |> stream(:users, Accounts.list_users())}
  end

  @impl true
  def handle_event("set-role", %{"id" => id, "role" => role}, socket)
      when role in ~w(user admin) do
    user = Accounts.get_user!(id)

    case Accounts.set_role(user, String.to_existing_atom(role)) do
      {:ok, user} ->
        {:noreply, stream_insert(socket, :users, user)}

      {:error, :last_admin} ->
        {:noreply, put_flash(socket, :error, "There must be at least one admin.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <.admin_tabs active={:users} />

      <.panel id="users-panel" title="Users">
        <ul id="users" phx-update="stream" class="divide-y divide-base-300">
          <li :for={{id, user} <- @streams.users} id={id} class="flex items-center gap-3 py-3 text-sm">
            <span class="truncate">{user.email}</span>
            <span class={[
              "rounded-full px-2 py-0.5 text-xs font-medium",
              if(user.role == :admin,
                do: "bg-primary/15 text-primary",
                else: "bg-base-300 text-base-content/70"
              )
            ]}>
              {user.role}
            </span>
            <span :if={user.id == @current_scope.user.id} class="text-xs text-base-content/50">you</span>
            <button
              :if={user.role == :user}
              id={"promote-#{user.id}"}
              phx-click="set-role"
              phx-value-id={user.id}
              phx-value-role="admin"
              data-confirm={"Make #{user.email} an admin?"}
              class="ml-auto rounded-lg px-3 py-1.5 transition hover:bg-base-300"
            >
              Make admin
            </button>
            <button
              :if={user.role == :admin}
              id={"demote-#{user.id}"}
              phx-click="set-role"
              phx-value-id={user.id}
              phx-value-role="user"
              data-confirm={"Remove admin rights from #{user.email}?"}
              class="ml-auto rounded-lg px-3 py-1.5 transition hover:bg-base-300"
            >
              Remove admin
            </button>
          </li>
        </ul>
      </.panel>
    </Layouts.app>
    """
  end
end
