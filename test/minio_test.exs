defmodule MinIOTest do
  use ExUnit.Case, async: true

  @moduletag :minio

  # uses https://min.io
  # docker run -d --rm -p 9000:9000 -p 9001:9001 minio/minio server /data --console-address ":9001"
  # docker exec minio mc alias set local http://localhost:9000 minioadmin minioadmin
  # docker exec minio mc mb local/testbucket

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
        access_key_id: System.get_env("MINIO_ACCESS_KEY", "minioadmin"),
        secret_access_key: System.get_env("MINIO_SECRET_KEY", "minioadmin"),
        region: System.get_env("MINIO_REGION", "us-east-1"),
        url: URI.parse(System.get_env("MINIO_ENDPOINT_URL", "http://localhost:9000"))
      ],
      extra
    )
  end

  defp unique_key(prefix) do
    "#{prefix}-#{System.system_time(:second)}-#{System.unique_integer([:positive])}"
  end

  test "HeadObject object that doesn't exist" do
    {uri, headers, body} =
      S3.build(config(method: :head, path: "/testbucket/ / eh? 🤔"))

    assert uri.path == "/testbucket/%20/%20eh%3F%20%F0%9F%A4%94"

    response = request!(:head, uri, headers, body)

    assert response.status == 404
    assert response.headers["x-minio-error-desc"] == ~s["The specified key does not exist."]
    assert response.body == ""
  end

  test "PutObject" do
    key = unique_key("my-bytes")

    # PubObject

    {uri, headers, body} =
      S3.build(
        config(
          method: :put,
          path: "/testbucket/#{key}",
          headers: [{"content-type", "application/octet-stream"}],
          body: <<0::size(8 * 1_000_000)>>
        )
      )

    response = request!(:put, uri, headers, body)

    assert response.status == 200
    assert response.headers["etag"] == ~s["879f4bba57ed37c9ec5e5aedf9864698"]
    assert response.body == ""

    # HeadObject

    {uri, headers, body} = S3.build(config(method: :head, path: "/testbucket/#{key}"))

    response = request!(:head, uri, headers, body)

    assert response.status == 200
    assert response.headers["content-length"] == "1000000"
    assert response.headers["content-type"] == "application/octet-stream"
    assert response.headers["etag"] == ~s["879f4bba57ed37c9ec5e5aedf9864698"]
    assert response.body == ""
  end

  test "chunked PutObject" do
    key = unique_key("my-streamed-bytes")

    # PutObject

    ### 10 chunks of 100KB
    stream = Stream.take(Stream.repeatedly(fn -> <<0::size(8 * 100_000)>> end), 10)

    {uri, headers, body = {:stream, _signed_stream}} =
      S3.build(
        config(
          method: :put,
          path: "/testbucket/#{key}",
          headers: [
            {"content-type", "application/octet-stream"},
            {"content-encoding", "aws-chunked"},
            {"x-amz-decoded-content-length", "1000000"}
          ],
          body: {:stream, stream}
        )
      )

    response = request!(:put, uri, headers, body)

    assert response.status == 200
    assert response.headers["etag"] == ~s["879f4bba57ed37c9ec5e5aedf9864698"]
    assert response.body == ""

    # HeadObject

    {uri, headers, body} = S3.build(config(method: :head, path: "/testbucket/#{key}"))

    response = request!(:head, uri, headers, body)

    assert response.status == 200
    assert response.headers["content-length"] == "1000000"
    assert response.headers["content-type"] == "application/octet-stream"
    assert response.headers["etag"] == ~s["879f4bba57ed37c9ec5e5aedf9864698"]
    assert response.body == ""
  end

  test "GetObject" do
    key = unique_key("my-bytes")

    # PutObject

    {uri, headers, body} =
      S3.build(
        config(
          method: :put,
          path: "/testbucket/#{key}",
          headers: [{"content-type", "application/octet-stream"}],
          body: <<0::size(8 * 1_000_000)>>
        )
      )

    response = request!(:put, uri, headers, body)

    assert response.status == 200
    assert response.headers["etag"] == ~s["879f4bba57ed37c9ec5e5aedf9864698"]
    assert response.body == ""

    # GetObject

    {uri, headers, body} = S3.build(config(method: :get, path: "/testbucket/#{key}"))

    response = request!(:get, uri, headers, body)

    assert response.status == 200
    assert response.headers["content-length"] == "1000000"
    assert response.headers["content-type"] == "application/octet-stream"
    assert response.headers["etag"] == ~s["879f4bba57ed37c9ec5e5aedf9864698"]
    assert byte_size(response.body) == 1_000_000
    assert response.body == <<0::size(8 * 1_000_000)>>

    # streaming GetObject

    {uri, headers, body} = S3.build(config(method: :get, path: "/testbucket/#{key}"))
    stream = fn packet, acc -> [packet | acc] end
    req = Finch.build(:get, uri, headers, body)
    assert {:ok, packets} = Finch.stream(req, @finch, _acc = [], stream)

    assert [{:status, 200}, {:headers, [_ | _]} | data_packets] = :lists.reverse(packets)

    data_packets = Enum.map(data_packets, fn {:data, data} -> data end)
    assert length(data_packets) > 1
    assert IO.iodata_length(data_packets) == 1_000_000
  end

  test "ListObjectsV2" do
    {uri, headers, body} =
      S3.build(
        config(
          method: :get,
          path: "/testbucket",
          query: %{"list-type" => 2}
        )
      )

    response = request!(:get, uri, headers, body)

    assert response.status == 200

    assert {:ok,
            {
              "ListBucketResult",
              [
                {"Name", ["testbucket"]},
                {"Prefix", []},
                {"KeyCount", [key_count]},
                {"MaxKeys", ["1000"]},
                {"IsTruncated", ["false"]}
                | contents
              ]
            }} = S3.xml(response.body)

    assert String.to_integer(key_count) == length(contents)
  end
end
