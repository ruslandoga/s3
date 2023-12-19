Small and experimental Amazon S3-compatible object storage "client" in a single file.

Inspired by
- https://gist.github.com/chrismccord/37862f1f8b1f5148644b75d20d1cb073 (single file, easy)
- https://github.com/aws-beam/aws-elixir (clients are structs, xmerl)
- https://github.com/ex-aws/ex_aws_s3 (streaming uploads and downloads)

Verified to work with Amazon S3, MinIO.

TODO: Wasabi, Backblaze B2, Cloudflare R2, DigitalOcean, and Scaleway.

#### Example using [MinIO](https://github.com/minio/minio) and [Finch](https://github.com/sneako/finch)

```console
$ docker run -d --rm -p 9000:9000 --name minio minio/minio server /data
$ docker exec minio mc alias set local http://localhost:9000 minioadmin minioadmin
$ docker exec minio mc mb local/testbucket
$ iex
```

```elixir
# Setup
Mix.install([:finch, {:s3, github: "ruslandoga/s3"}])
Finch.start_link(name: MinIO.Finch)

config = fn options ->
  Keyword.merge(
    [
      access_key_id: "minioadmin",
      secret_access_key: "minioadmin",
      url: "http://localhost:9000",
      region: "us-east-1"
    ],
    options
  )
end
```

```elixir
# PutObject
{uri, headers, body} =
  S3.build(
    config.(
      method: :put,
      headers: [{"content-type", "application/octet-stream"}],
      path: "/testbucket/my-bytes",
      body: <<0::size(8 * 1_000_000)>>
    )
  )

req = Finch.build(:put, uri, headers, body)
200 = Finch.request!(req, MinIO.Finch).status
```
```elixir
# HeadObject
{uri, headers, body} = S3.build(config.(method: :head, path: "/testbucket/my-bytes"))
req = Finch.build(:head, uri, headers, body)

%{
  "content-length" => "1000000",
  "content-type" => "application/octet-stream",
  "etag" => "\"879f4bba57ed37c9ec5e5aedf9864698\""
  # etc.
} = Map.new(Finch.request!(req, MinIO.Finch).headers)
```
```elixir
# stream GetObject
{uri, headers, body} = S3.build(config.(method: :get, path: "/testbucket/my-bytes"))
req = Finch.build(:get, uri, headers, body)

stream = fn packet, _acc ->
  with {:data, data} <- packet do
    IO.inspect(byte_size(data), label: "bytes received")
  end
end

Finch.stream(req, MinIO.Finch, _acc = [], stream)
# bytes received: 147404
# bytes received: 408300
# bytes received: 408300
# bytes received: 35996
```
```elixir
# chunked PutObject
# https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-streaming.html
stream = Stream.repeatedly(fn -> <<0::size(8 * 100_000)>> end)
stream = Stream.take(stream, 10)

{uri, headers, body = {:stream, _signed_stream}} =
  S3.build(
    config.(
      method: :put,
      headers: [
        {"content-type", "application/octet-stream"},
        {"content-encoding", "aws-chunked"},
        {"x-amz-decoded-content-length", "1000000"}
      ],
      path: "/testbucket/my-bytestream",
      body: {:stream, stream}
    )
  )

req = Finch.build(:put, uri, headers, body)
200 = Finch.request!(req, MinIO.Finch).status
```
```elixir
# ListObjectsV2
# https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListObjectsV2.html
{uri, headers, body} = S3.build(config.(method: :get, path: "/testbucket", query: %{"list-type" => 2}))
req = Finch.build(:get, uri, headers, body)

{:ok,
 {
   "ListBucketResult",
   [
     {"Name", ["testbucket"]},
     {"Prefix", []},
     {"KeyCount", ["2"]},
     {"MaxKeys", ["1000"]},
     {"IsTruncated", ["false"]},
     {
       "Contents",
       [
         {"Key", ["my-bytes"]},
         {"LastModified", ["2023-12-14T08:54:40.085Z"]},
         {"ETag", ["\"879f4bba57ed37c9ec5e5aedf9864698\""]},
         {"Size", ["1000000"]},
         {"StorageClass", ["STANDARD"]}
       ]
     }
     | _etc
   ]
 }} = S3.xml(Finch.request!(req, MinIO.Finch).body)
```

```console
$ docker stop minio
```

TODO:
- [Signed Upload Form](https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-UsingHTTPPOST.html)
- [Signed URL](https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-query-string-auth.html)
- [DeleteObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_DeleteObject.html)
- [DeleteObjects](https://docs.aws.amazon.com/AmazonS3/latest/API/API_DeleteObjects.html)
