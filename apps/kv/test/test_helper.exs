# ExUnit.start()

exclude =
  if Node.alive?(), do: [], else: [distributed: true]

ExUnit.start(exclude: exclude)
