defmodule ExpoController.Builds.Build do
  @moduledoc """
  Represents a build submission in the system.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "builds" do
    field :platform, Ecto.Enum, values: [:ios, :android]
    field :status, Ecto.Enum,
      values: [:pending, :assigned, :building, :completed, :failed, :cancelled]
    field :source_path, :string
    field :certs_path, :string
    field :result_path, :string
    field :error_message, :string
    field :access_token, :string
    field :last_heartbeat_at, :utc_datetime
    field :otp, :string
    field :otp_expires_at, :utc_datetime
    field :vm_token, :string
    field :vm_token_expires_at, :utc_datetime

    belongs_to :worker, ExpoController.Workers.Worker, type: :string, foreign_key: :worker_id
    has_many :logs, ExpoController.Builds.BuildLog

    timestamps(type: :utc_datetime, inserted_at: :submitted_at)
  end

  @doc false
  def changeset(build, attrs) do
    build
    |> cast(attrs, [
      :id,
      :platform,
      :status,
      :source_path,
      :certs_path,
      :result_path,
      :error_message,
      :access_token,
      :worker_id,
      :last_heartbeat_at,
      :otp,
      :otp_expires_at,
      :vm_token,
      :vm_token_expires_at
    ])
    |> validate_required([:id, :platform])
    |> validate_inclusion(:platform, [:ios, :android])
    |> validate_inclusion(:status, [:pending, :assigned, :building, :completed, :failed, :cancelled])
    |> unique_constraint(:id, name: :builds_pkey)
  end

  @doc """
  Generate a one-time password for VM authentication.
  OTP expires in 10 minutes.
  """
  def generate_otp_changeset(build) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    otp_expires_at = DateTime.add(now, 600, :second) # 10 minutes

    change(build,
      otp: generate_token(),
      otp_expires_at: otp_expires_at
    )
  end

  @doc """
  Generate a temporary VM token (after OTP authentication).
  VM token expires in 2 hours.
  """
  def generate_vm_token_changeset(build) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    vm_token_expires_at = DateTime.add(now, 7200, :second) # 2 hours

    change(build,
      vm_token: generate_token(),
      vm_token_expires_at: vm_token_expires_at
    )
  end

  defp generate_token do
    :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
  end

  @doc """
  Changeset for creating a new build.
  Generates access_token if not provided.
  """
  def create_changeset(attrs) do
    changeset = %__MODULE__{}
    |> changeset(attrs)
    |> put_change(:status, :pending)
    |> validate_required([:id, :platform, :status])

    # Generate access_token if not provided
    if get_field(changeset, :access_token) do
      changeset
    else
      put_change(changeset, :access_token, generate_access_token())
    end
  end

  @doc """
  Generates a secure random access token (32 bytes, base64url encoded).
  """
  def generate_access_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  @doc """
  Changeset for assigning a build to a worker.
  Generates OTP for VM authentication.
  """
  def assign_changeset(build, worker_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    otp_expires_at = DateTime.add(now, 600, :second) # 10 minutes

    build
    |> change(
      status: :assigned,
      worker_id: worker_id,
      otp: generate_token(),
      otp_expires_at: otp_expires_at
    )
    |> validate_required([:worker_id])
  end

  @doc """
  Changeset for updating heartbeat.
  """
  def heartbeat_changeset(build) do
    change(build, last_heartbeat_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Changeset for completing a build.
  """
  def complete_changeset(build, result_path) do
    build
    |> change(status: :completed, result_path: result_path)
    |> validate_required([:result_path])
  end

  @doc """
  Changeset for failing a build.
  """
  def fail_changeset(build, error_message) do
    build
    |> change(status: :failed, error_message: error_message)
    |> validate_required([:error_message])
  end
end
