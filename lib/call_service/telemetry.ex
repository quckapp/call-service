defmodule CallService.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_arg) do
    children = [{Telemetry.Metrics.ConsoleReporter, metrics: metrics()}]
    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      counter("call.initiated.count"),
      counter("call.answered.count"),
      counter("call.ended.count"),
      counter("call.rejected.count"),
      summary("call.duration.seconds"),
      last_value("call.active.count"),
      counter("huddle.created.count"),
      counter("huddle.joined.count"),
      summary("webrtc.signaling.duration", unit: {:native, :millisecond})
    ]
  end
end
