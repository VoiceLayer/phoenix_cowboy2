# PhoenixCowboy2

This is a handler for Cowboy 2 based off of the work on @potatosalad's fork
available at https://github.com/potatosalad/phoenix/tree/cowboy2

## Installation

  1. Add `phoenix_cowboy2` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:phoenix_cowboy2, github: "voicelayer/phoenix_cowboy2"}]
    end
    ```

  2. Ensure `phoenix_cowboy2` is started before your application:

    ```elixir
    def application do
      [applications: [:phoenix_cowboy2]]
    end
    ```

## Sample Application

### Phoenix

A sample application with plug is available at
https://github.com/voicelayer/phoenix_cowboy2_example
