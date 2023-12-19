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

Benchee.run(
  %{
    "S3.build/1" => &S3.build/1
  },
  memory_time: 2,
  profile_after: true,
  inputs: %{
    "PutObject" =>
      config.(
        method: :put,
        headers: [{"content-type", "application/octet-stream"}],
        path: "/testbucket/my-bytes",
        body: <<0::size(8 * 1_000_000)>>
      ),
    "GetObject" => config.(method: :get, path: "/testbucket/my-bytes")
  }
)
