defmodule DcompWeb.AdminLive.Users do
  @moduledoc "Admin: who has an account and who is an admin."
  use DcompWeb, :live_view

  import DcompWeb.GameComponents

  alias Dcomp.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Users · Admin")
     |> assign(:new_form, new_form())
     |> assign(:password_user_id, nil)
     |> assign(:password_form, nil)
     |> stream(:users, Accounts.list_users())}
  end

  defp new_form(params \\ %{}, action \\ nil) do
    params |> Accounts.change_new_user() |> Map.put(:action, action) |> to_form(as: :user)
  end

  defp role_param(%{"role" => "admin"}), do: :admin
  defp role_param(_), do: :user

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

  def handle_event("validate-new", %{"user" => params}, socket) do
    {:noreply, assign(socket, :new_form, new_form(params, :validate))}
  end

  def handle_event("create-user", %{"user" => params}, socket) do
    case Accounts.create_user(params, role_param(params)) do
      {:ok, user} ->
        {:noreply,
         socket
         |> stream_insert(:users, user, at: 0)
         |> assign(:new_form, new_form())
         |> put_flash(:info, "Created #{user.email}.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :new_form, to_form(changeset, as: :user))}
    end
  end

  def handle_event("open-password", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    {:noreply,
     socket
     |> close_password()
     |> assign(:password_user_id, user.id)
     |> assign(:password_form, password_form(user))
     |> stream_insert(:users, user)}
  end

  def handle_event("close-password", _params, socket), do: {:noreply, close_password(socket)}

  def handle_event("validate-password", %{"password" => params}, socket) do
    user = Accounts.get_user!(socket.assigns.password_user_id)
    {:noreply, assign(socket, :password_form, password_form(user, params, :validate))}
  end

  def handle_event("set-password", %{"password" => params}, socket) do
    user = Accounts.get_user!(socket.assigns.password_user_id)

    case Accounts.update_user_password(user, params) do
      {:ok, {user, _expired_tokens}} ->
        {:noreply,
         socket
         |> close_password()
         |> stream_insert(:users, user)
         |> put_flash(
           :info,
           "Password updated for #{user.email}. Their sessions were signed out."
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :password_form, to_form(changeset, as: :password))}
    end
  end

  defp password_form(user, params \\ %{}, action \\ nil) do
    user
    |> Accounts.change_user_password(params, hash_password: false)
    |> Map.put(:action, action)
    |> to_form(as: :password)
  end

  # Closes the open password form and re-renders its row (stream items only update on insert).
  defp close_password(%{assigns: %{password_user_id: nil}} = socket), do: socket

  defp close_password(%{assigns: %{password_user_id: id}} = socket) do
    socket
    |> assign(:password_user_id, nil)
    |> assign(:password_form, nil)
    |> stream_insert(:users, Accounts.get_user!(id))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <.admin_tabs active={:users} />

      <.panel id="new-user-panel" title="Add a user">
        <.form
          for={@new_form}
          id="new-user-form"
          phx-change="validate-new"
          phx-submit="create-user"
          class="grid gap-x-4 sm:grid-cols-3"
        >
          <.input field={@new_form[:email]} type="email" label="Email" autocomplete="off" required />
          <.input
            field={@new_form[:password]}
            type="password"
            label="Password (12 characters or more)"
            autocomplete="new-password"
            required
          />
          <.input
            field={@new_form[:role]}
            type="select"
            label="Role"
            options={[{"User", "user"}, {"Admin", "admin"}]}
          />
          <div class="sm:col-span-3">
            <button
              id="create-user"
              type="submit"
              phx-disable-with="Creating..."
              class="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-content transition hover:opacity-90"
            >
              Create user
            </button>
          </div>
        </.form>
      </.panel>

      <.panel id="users-panel" title="Users">
        <ul id="users" phx-update="stream" class="divide-y divide-base-300">
          <li
            :for={{id, user} <- @streams.users}
            id={id}
            class="flex flex-wrap items-center gap-3 py-3 text-sm"
          >
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
              id={"set-password-#{user.id}"}
              phx-click="open-password"
              phx-value-id={user.id}
              class="ml-auto rounded-lg px-3 py-1.5 transition hover:bg-base-300"
            >
              Set password
            </button>
            <button
              :if={user.role == :user}
              id={"promote-#{user.id}"}
              phx-click="set-role"
              phx-value-id={user.id}
              phx-value-role="admin"
              data-confirm={"Make #{user.email} an admin?"}
              class="rounded-lg px-3 py-1.5 transition hover:bg-base-300"
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
              class="rounded-lg px-3 py-1.5 transition hover:bg-base-300"
            >
              Remove admin
            </button>
            <.form
              :if={@password_user_id == user.id}
              for={@password_form}
              id={"password-form-#{user.id}"}
              phx-change="validate-password"
              phx-submit="set-password"
              class="flex w-full flex-wrap items-start gap-3"
            >
              <.input
                field={@password_form[:password]}
                type="password"
                placeholder="New password (12 characters or more)"
                autocomplete="new-password"
                required
              />
              <button
                id={"save-password-#{user.id}"}
                type="submit"
                class="rounded-lg bg-primary px-3 py-2 text-primary-content transition hover:opacity-90"
              >
                Save password
              </button>
              <button
                type="button"
                phx-click="close-password"
                class="rounded-lg px-3 py-2 transition hover:bg-base-300"
              >
                Cancel
              </button>
            </.form>
          </li>
        </ul>
      </.panel>
    </Layouts.app>
    """
  end
end
