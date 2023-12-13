defmodule S3Test do
  use ExUnit.Case

  @config [
    access_key_id: "AKIAZZM67ULNV4CSXW4B",
    secret_access_key: "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",
    base_url: URI.parse("https://vl3tueq.s3.ap-southeast-1.amazonaws.com"),
    region: "ap-southeast-1",
    utc_now: ~U[2023-12-13 11:22:36.220710Z]
  ]

  test "simple HeadObject" do
    {uri, headers, body} =
      S3.build([method: :head, path: "Screenshot 2023-11-27 at 20.39.07.png"] ++ @config)

    assert uri == %URI{
             scheme: "https",
             authority: "vl3tueq.s3.ap-southeast-1.amazonaws.com",
             userinfo: nil,
             host: "vl3tueq.s3.ap-southeast-1.amazonaws.com",
             port: 443,
             path: "/Screenshot%202023-11-27%20at%2020.39.07.png",
             # TODO
             query: "&",
             fragment: nil
           }

    assert headers == [
             {
               "authorization",
               """
               AWS4-HMAC-SHA256 Credential=AKIAZZM67ULNV4CSXW4B/20231213/ap-southeast-1/s3/aws4_request,\
               SignedHeaders=host;x-amz-content-sha256;x-amz-date,\
               Signature=0b89231cade2e5a6fb33beb9b21e06f7495ce9e770f7c0b2f4a69c7710e49a02\
               """
             },
             {"host", "vl3tueq.s3.ap-southeast-1.amazonaws.com"},
             {"x-amz-content-sha256",
              "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
             {"x-amz-date", "20231213T112236Z"}
           ]

    assert body == []
  end
end
