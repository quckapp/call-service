defmodule CallService.Guardian do
  use Guardian, otp_app: :call_service

  def subject_for_token(user_id, _claims), do: {:ok, to_string(user_id)}
  def resource_from_claims(%{"sub" => user_id}), do: {:ok, user_id}
  def resource_from_claims(_claims), do: {:error, :invalid_claims}
end
