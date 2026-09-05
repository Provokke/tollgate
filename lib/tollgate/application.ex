defmodule Tollgate.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Tollgate.Server, name: Tollgate.Server}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Tollgate.Supervisor)
  end
end
