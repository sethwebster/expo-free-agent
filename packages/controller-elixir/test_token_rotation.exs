# Test token rotation optimization
alias ExpoController.{Repo, Workers}

# Clean slate
Repo.delete_all(Workers.Worker)

# Create worker
{:ok, worker} = Workers.register_worker(%{
  id: "test-worker",
  name: "Test Worker",
  capabilities: %{}
})

IO.puts("Initial token: #{String.slice(worker.access_token, 0..10)}...")
IO.puts("Expires at: #{worker.access_token_expires_at}")
initial_token = worker.access_token

# Heartbeat immediately - should NOT rotate (token just created, 90s remaining)
{:ok, worker2} = Workers.heartbeat_worker(worker)
IO.puts("\nAfter immediate heartbeat:")
IO.puts("Token: #{String.slice(worker2.access_token, 0..10)}...")
IO.puts("Expires at: #{worker2.access_token_expires_at}")
IO.puts("Token changed? #{worker2.access_token != initial_token}")

# Simulate time passing - token expires in 25 seconds
future_expiry = DateTime.add(DateTime.utc_now(), 25, :second)
Repo.update!(Workers.Worker.changeset(worker2, %{access_token_expires_at: future_expiry}))

worker3 = Repo.get!(Workers.Worker, "test-worker")
IO.puts("\nAfter simulating near-expiry (25s remaining):")
IO.puts("Expires at: #{worker3.access_token_expires_at}")

# Heartbeat with near-expiry - SHOULD rotate
{:ok, worker4} = Workers.heartbeat_worker(worker3)
IO.puts("\nAfter heartbeat with near-expiry:")
IO.puts("Token: #{String.slice(worker4.access_token, 0..10)}...")
IO.puts("Expires at: #{worker4.access_token_expires_at}")
IO.puts("Token changed? #{worker4.access_token != worker3.access_token}")

# Cleanup
Repo.delete_all(Workers.Worker)
