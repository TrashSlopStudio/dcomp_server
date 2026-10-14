defmodule DcompWeb.Router do
  use DcompWeb, :router

  import DcompWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug DcompWeb.Locale
    plug :fetch_live_flash
    plug :put_root_layout, html: {DcompWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_api_key do
    plug DcompWeb.Plugs.RequireApiKey
  end

  scope "/", DcompWeb do
    pipe_through :browser

    live_session :public,
      on_mount: [{DcompWeb.Locale, :default}, {DcompWeb.UserAuth, :mount_current_scope}] do
      live "/", GameLive.Index
      live "/games/:slug", GameLive.Show
    end
  end

  scope "/", DcompWeb do
    pipe_through :browser

    get "/locale/:locale", LocaleController, :update
  end

  # Uploaded game images. No session needed, so no pipeline.
  scope "/", DcompWeb do
    get "/uploads/:name", UploadController, :show
  end

  # Machine-to-machine (GitHub Actions): no session or CSRF, authenticated by the global API key.
  scope "/api", DcompWeb do
    pipe_through [:api, :require_api_key]

    post "/games/:slug/sync", SyncController, :create
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:dcomp, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DcompWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Admin area: logged in AND admin. The plugs guard the first (HTTP) request; the live_session's
  # on_mount hook re-checks on every live navigation, where plugs don't run.
  scope "/admin", DcompWeb.AdminLive, as: :admin do
    pipe_through [:browser, :require_authenticated_user, :require_admin]

    live_session :admin,
      on_mount: [{DcompWeb.Locale, :default}, {DcompWeb.UserAuth, :require_admin}] do
      live "/games", Games, :index
      live "/games/new", Games, :new
      live "/games/:id/edit", Games, :edit
      live "/settings", Settings, :edit
      live "/users", Users, :index
    end
  end

  ## Authentication routes

  scope "/", DcompWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", DcompWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
