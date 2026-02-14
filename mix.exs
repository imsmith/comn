defmodule Comn.MixProject do
  use Mix.Project

  def project do
    [
      app: :comn,
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      {:faker, "~> 0.18", only: :test},
      {:cabbage, "~> 0.4.1", only: :test},
      {:gnat, "~> 1.11"}
    ]
  end
end
