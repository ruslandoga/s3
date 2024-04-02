defmodule R2Test do
  use ExUnit.Case, async: true

  @moduletag :r2

  # uses https://developers.cloudflare.com/r2/api/s3/api/

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
        access_key_id: System.fetch_env!("R2_ACCESS_KEY"),
        secret_access_key: System.fetch_env!("R2_SECRET_ACCESS_KEY"),
        region: System.get_env("R2_REGION", "auto"),
        url: URI.parse(System.fetch_env!("R2_ENDPOINT_URL"))
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

  test "PutObject" do
    key = unique_key("my-bytes")

    # PubObject

    {uri, headers, body} =
      S3.build(
        config(
          method: :put,
          path: "/#{key}",
          headers: [{"content-type", "application/octet-stream"}],
          body: <<0::size(8 * 1_000_000)>>
        )
      )

    response = request!(:put, uri, headers, body)

    assert response.status == 200
    assert response.headers["etag"] == ~s["879f4bba57ed37c9ec5e5aedf9864698"]
    assert response.body == ""

    # HeadObject

    {uri, headers, body} = S3.build(config(method: :head, path: "/#{key}"))

    response = request!(:head, uri, headers, body)

    assert response.status == 200
    assert response.headers["content-length"] == "1000000"
    assert response.headers["content-type"] == "application/octet-stream"
    assert response.headers["etag"] == ~s["879f4bba57ed37c9ec5e5aedf9864698"]
    assert response.body == ""
  end

  # not supported, see https://developers.cloudflare.com/r2/api/s3/api/
  @tag :skip
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

    {uri, headers, body} = S3.build(config(method: :head, path: "/#{key}"))

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
          path: "/#{key}",
          headers: [{"content-type", "application/octet-stream"}],
          body: <<0::size(8 * 1_000_000)>>
        )
      )

    response = request!(:put, uri, headers, body)

    assert response.status == 200
    assert response.headers["etag"] == ~s["879f4bba57ed37c9ec5e5aedf9864698"]
    assert response.body == ""

    # GetObject

    {uri, headers, body} = S3.build(config(method: :get, path: "/#{key}"))

    response = request!(:get, uri, headers, body)

    assert response.status == 200
    assert response.headers["content-length"] == "1000000"
    assert response.headers["content-type"] == "application/octet-stream"
    assert response.headers["etag"] == ~s["879f4bba57ed37c9ec5e5aedf9864698"]
    assert byte_size(response.body) == 1_000_000
    assert response.body == <<0::size(8 * 1_000_000)>>

    # streaming GetObject

    {uri, headers, body} = S3.build(config(method: :get, path: "/#{key}"))
    stream = fn packet, acc -> [packet | acc] end
    req = Finch.build(:get, uri, headers, body)
    assert {:ok, packets} = Finch.stream(req, @finch, _acc = [], stream)

    assert [{:status, 200}, {:headers, [_ | _]} | data_packets] = :lists.reverse(packets)

    data_packets = Enum.map(data_packets, fn {:data, data} -> data end)
    assert length(data_packets) > 1
    assert IO.iodata_length(data_packets) == 1_000_000
  end

  @tag :delete_all
  test "ListObjectsV2 -> DeleteObjects" do
    {uri, headers, body} =
      S3.build(
        config(
          method: :get,
          path: "/",
          query: %{"list-type" => 2}
        )
      )

    response = request!(:get, uri, headers, body)
    assert response.status == 200

    assert {:ok, {"ListBucketResult", list_bucket_result}} = S3.xml(response.body)

    assert {[contents],
            [
              {"Name", [_bucket]},
              {"IsTruncated", ["false"]},
              {"MaxKeys", ["1000"]},
              {"KeyCount", [key_count]}
            ]} =
             :proplists.split(list_bucket_result, ["Contents"])

    key_count = String.to_integer(key_count)
    assert key_count == length(contents)

    if key_count > 0 do
      objects =
        Enum.map(contents, fn {"Contents", contents} ->
          {"Object", [List.keyfind!(contents, "Key", 0)]}
        end)

      xml = S3.xml({"Delete", objects})
      content_md5 = Base.encode64(:crypto.hash(:md5, xml))

      {uri, headers, body} =
        S3.build(
          config(
            method: :post,
            path: "/",
            query: %{"delete" => ""},
            headers: [{"content-md5", content_md5}],
            body: xml
          )
        )

      response = request!(:post, uri, headers, body)

      assert response.status == 200
      assert response.headers["content-type"] == "application/xml"
      assert {:ok, {"DeleteResult", deleted}} = S3.xml(response.body)

      deleted_keys =
        Enum.map(deleted, fn deleted ->
          {"Deleted", [{"Key", [key]}]} = deleted
          key
        end)

      contents_keys =
        Enum.map(contents, fn {"Contents", contents} ->
          {"Key", [key]} = List.keyfind!(contents, "Key", 0)
          key
        end)

      assert deleted_keys == contents_keys
    end
  end
end
