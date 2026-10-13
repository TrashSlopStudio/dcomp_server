defmodule DcompWeb.UserSessionHTML do
  use DcompWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:dcomp, Dcomp.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
