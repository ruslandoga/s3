defmodule S3.MinIOTest do
  use ExUnit.Case

  # uses https://min.io
  # docker run -d --rm -p 9000:9000 -p 9001:9001 -v ./tmp/minio:/data minio/minio server /data --console-address ":9001"
  @moduletag :minio
  @finch __MODULE__.Finch

  setup do
    start_supervised!({Finch, name: @finch})
    :ok
  end

  defp config(extra) do
    Keyword.merge(
      [
        access_key_id: System.get_env("MINIO_ACCESS_KEY", "minioadmin"),
        secret_access_key: System.get_env("MINIO_SECRET_KEY", "minioadmin"),
        region: System.get_env("MINIO_REGION", "us-east-1"),
        url: URI.parse(System.get_env("MINIO_ENDPOINT_URL", "http://localhost:9000"))
      ],
      extra
    )
  end

  test "simple HeadObject" do
    # TODO /testbuicket/eh? doesn't work (invalid signature)
    {uri, headers, body} = S3.build(config(path: "/testbucket/eh", method: :head))

    req = Finch.build(:head, uri, headers, body)
    assert {:ok, %Finch.Response{status: 404} = resp} = Finch.request(req, @finch)

    assert %{"x-minio-error-desc" => ~s["The specified key does not exist."]} =
             Map.new(resp.headers)

    assert resp.body == ""
  end
end
