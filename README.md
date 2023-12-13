Small and experimental Amazon S3-compatible object storage "client" in a single file.

Inspired by
- https://gist.github.com/chrismccord/37862f1f8b1f5148644b75d20d1cb073 (single file, easy)
- https://github.com/aws-beam/aws-elixir (clients are structs, xmerl)
- https://github.com/ex-aws/ex_aws_s3 (streaming uploads and downloads)

Verified to work with Amazon S3, Wasabi, Backblaze B2, Cloudflare R2, DigitalOcean, and Scaleway.

Examples:

```elixir
{:ok, finch} = Finch.start_link([])

config = [
  access_key_id: "AKIAZZM67ULNV4CSXW4B",
  secret_access_key: "pHMekdDD1nE4tOJdZ92ziz8qy0mbhJLrfjHkuRy8",
  base_url: URI.parse("https://vl3tueq.s3.ap-southeast-1.amazonaws.com"),
  region: "ap-southeast-1"
]
```

- Simple [HeadObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_HeadObject.html)

```elixir
{uri, headers, body} = S3.build(method: :head, path: "Screenshot 2023-11-27 at 20.39.07.png" | config)

request = Finch.build(:head, uri, headers, body)
{:ok, %Finch.Response{status: 201, headers: headers}} = Finch.request(request, finch)

[] = headers
```

- Simple [GetObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObject.html)

```elixir
{uri, headers, body} = S3.build(method: :get, path: "Screenshot 2023-11-27 at 20.39.07.png" | config)

request = Finch.build(:get, uri, headers, body)
{:ok, %Finch.Response{status: 200, body: body}} = Finch.request(request, finch)

<<_::123-bytes>> = body
```

- Streaming [GetObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObject.html)

```elixir
{uri, headers, body} = S3.build(method: :get, path: "Screenshot 2023-11-27 at 20.39.07.png" | config)

request = Finch.stream(:get, uri, headers, body)
{:ok, %Finch.Response{status: 200}} = Finch.request(request, finch)

%{} = File.stat!("screenshot.png")
```

- Simple [PutObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutObject.html)

```elixir
{uri, headers, body} =
  S3.build(
    method: :put,
    path: "空",
    headers: [{"content-type", "application/octet-stream"}],
    # 50000 zero bytes
    body: <<0::50_000>>,
    | config
  )

request = Finch.build(:put, uri, headers, body)
{:ok, %Finch.Response{status: 201, headers: headers, body: body}} = Finch.request(request, finch)

[] = headers
%{} = S3.xml(body)
```

- [Chunked](https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-streaming.html) [PutObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutObject.html)

```elixir
# 50 chunks of 1000 zero bytes
zeroes = Stream.repeatedly(<<0::1000>>) |> Stream.take(50)

{uri, headers, body} =
  S3.build(
    method: :put,
    path: "/streamed/空",
    headers: [{"content-type", "application/octet-stream"}],
    body: {:stream, zeroes}
    | config
  )

request = Finch.build(:put, uri, headers, {:stream, body})
{:ok, %Finch.Response{status: 201, headers: headers, body: body}} = Finch.request(request, finch)

[] = headers
%{} = S3.xml(body)
```

- [Signed Upload Form](https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-UsingHTTPPOST.html)

```elixir
```

- [Signed URL](https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-query-string-auth.html)
- Simple [DeleteObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_DeleteObject.html)
- Simple [DeleteObjects](https://docs.aws.amazon.com/AmazonS3/latest/API/API_DeleteObjects.html)
- Paginated [ListObjectsV2](https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListObjectsV2.html)
