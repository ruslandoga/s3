defmodule B2Test do
  use ExUnit.Case, async: true

  @moduletag :b2

  # uses https://www.backblaze.com/docs/cloud-storage-s3-compatible-api

  @finch __MODULE__.Finch

  setup do
    start_supervised!({Finch, name: @finch})
    :ok
  end

  defp request!(method, uri, headers, body) do
    Finch.build(method, uri, headers, body)
    |> Finch.request!(@finch)
    |> Map.update!(:headers, &Map.new/1)
  end

  defp config(extra) do
    Keyword.merge(
      [
        access_key_id: System.fetch_env!("B2_ACCESS_KEY"),
        secret_access_key: System.fetch_env!("B2_SECRET_ACCESS_KEY"),
        region: System.fetch_env!("B2_REGION"),
        url: URI.parse(System.fetch_env!("B2_ENDPOINT_URL"))
      ],
      extra
    )
  end

  defp unique_key(prefix) do
    "#{prefix}-#{System.system_time(:second)}-#{System.unique_integer([:positive])}"
  end

  test "HeadObject object that doesn't exist" do
    {uri, headers, body} = S3.build(config(method: :head, path: "/ / eh? 🤔"))
    assert String.ends_with?(uri.path, "/%20/%20eh%3F%20%F0%9F%A4%94")

    response = request!(:head, uri, headers, body)
    assert response.status == 404
    assert response.body == ""
  end
end
