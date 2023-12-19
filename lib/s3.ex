defmodule S3 do
  @moduledoc "Small S3-compatible API request builder and stuff"

  # TODO hide access_key_id and secret_access_key from inspect / logs

  @type headers :: [{String.t(), String.t()}]

  @type option ::
          {:access_key_id, String.t()}
          | {:secret_access_key, String.t()}
          | {:url, URI.t()}
          | {:host, String.t()}
          | {:region, String.t()}
          | {:method, :get | :post | :head | :patch | :delete | :options | :put | String.t()}
          | {:path, String.t()}
          | {:query, Enumerable.t()}
          | {:headers, headers}
          | {:body, iodata | {:stream, Enumerable.t()}}
          | {:utc_now, DateTime.t()}

  @type options :: [option]

  @spec build(options) :: {URI.t(), headers, body :: iodata | Enumerable.t()}
  def build(options) do
    access_key_id = Keyword.fetch!(options, :access_key_id)
    secret_access_key = Keyword.fetch!(options, :secret_access_key)
    url = Keyword.fetch!(options, :url)
    host = Keyword.get(options, :host)
    path = Keyword.get(options, :path) || "/"
    query = Keyword.get(options, :query) || []
    region = Keyword.fetch!(options, :region)
    method = Keyword.fetch!(options, :method)
    headers = Keyword.get(options, :headers) || []
    body = Keyword.get(options, :body) || []

    # hidden options
    service = Keyword.get(options, :service, "s3")
    utc_now = Keyword.get(options, :utc_now) || DateTime.utc_now()

    amz_content_sha256 =
      case body do
        # https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-streaming.html
        {:stream, _stream} -> "STREAMING-AWS4-HMAC-SHA256-PAYLOAD"
        _ -> hex_sha256(body)
      end

    amz_date = Calendar.strftime(utc_now, "%Y%m%dT%H%M%SZ")

    headers =
      Enum.map(headers, fn {k, v} -> {String.downcase(k), v} end)
      |> put_header("host", host || url.host)
      |> put_header("x-amz-content-sha256", amz_content_sha256)
      |> put_header("x-amz-date", amz_date)
      |> Enum.sort_by(fn {k, _} -> k end)

    # TODO method() to ensure only valid atoms are allowed
    method = String.upcase(to_string(method))

    query = encode_query(url.query, query)
    path = path |> Path.split() |> Enum.map(&:uri_string.quote/1) |> Path.join()
    path = Path.join(url.path || "/", path)

    amz_short_date = String.slice(amz_date, 0, 8)

    scope = IO.iodata_to_binary([amz_short_date, ?/, region, ?/, service, ?/, "aws4_request"])

    signed_headers =
      headers
      |> Enum.map(fn {k, _} -> k end)
      |> Enum.intersperse(?;)
      |> IO.iodata_to_binary()

    canonical_request = [
      method,
      ?\n,
      path,
      ?\n,
      query,
      ?\n,
      Enum.map(headers, fn {k, v} -> [k, ?:, v, ?\n] end),
      ?\n,
      signed_headers,
      ?\n,
      amz_content_sha256
    ]

    string_to_sign = [
      "AWS4-HMAC-SHA256\n",
      amz_date,
      ?\n,
      scope,
      ?\n,
      hex_sha256(canonical_request)
    ]

    signing_key =
      ["AWS4" | secret_access_key]
      |> hmac_sha256(amz_short_date)
      |> hmac_sha256(region)
      |> hmac_sha256(service)
      |> hmac_sha256("aws4_request")

    signature = hex_hmac_sha256(signing_key, string_to_sign)

    authorization = """
    AWS4-HMAC-SHA256 Credential=#{access_key_id}/#{scope},\
    SignedHeaders=#{signed_headers},\
    Signature=#{signature}\
    """

    headers = [{"authorization", authorization} | headers]

    body =
      case body do
        # TODO https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-streaming.html
        {:stream, _stream} -> raise "sigv4-streaming not yet implemented"
        _ -> body
      end

    {%URI{url | query: query, path: path}, headers, body}
  end

  # TODO
  @spec encode_query(String.t() | nil, Enumerable.t() | nil) :: iodata
  defp encode_query(nil, nil), do: []
  defp encode_query(nil, q), do: URI.encode_query(q)
  defp encode_query(q, nil), do: q
  defp encode_query(q1, q2), do: q1 <> "&" <> URI.encode_query(q2)

  @compile inline: [put_header: 3]
  defp put_header(headers, key, value), do: [{key, value} | List.keydelete(headers, key, 1)]
  @compile inline: [hex: 1]
  defp hex(value), do: Base.encode16(value, case: :lower)
  @compile inline: [sha256: 1]
  defp sha256(value), do: :crypto.hash(:sha256, value)
  @compile inline: [hmac_sha256: 2]
  defp hmac_sha256(secret, value), do: :crypto.mac(:hmac, :sha256, secret, value)
  @compile inline: [hex_sha256: 1]
  defp hex_sha256(value), do: hex(sha256(value))
  @compile inline: [hex_hmac_sha256: 2]
  defp hex_hmac_sha256(secret, value), do: hex(hmac_sha256(secret, value))

  @type xml_node :: {String.t(), xml_node()}

  @spec xml(binary) :: {:ok, [xml_node]} | {:error, any}
  def xml(xml) when is_binary(xml) do
    # TODO
    # See: https://elixirforum.com/t/utf-8-issue-with-erlang-xmerl-scan-function/1668/9
    # xml = :erlang.binary_to_list(xml)

    result =
      :xmerl_sax_parser.stream(xml,
        event_fun: &__MODULE__.xml_event_fun/3,
        external_entities: :none
      )

    case result do
      {:ok, xml, ""} -> {:ok, xml}
      # TODO incomplete or extra -> error
      {:error, _reason} = e -> e
    end
  end

  # based on https://github.com/qcam/saxy/blob/master/lib/saxy/simple_form/handler.ex
  @doc false
  def xml_event_fun({:startElement, _, tag_name, _, _}, _location, stack) do
    [{tag_name, _content = []} | stack]
  end

  # TODO compare maps vs tuples vs two-el lists

  def xml_event_fun({:characters, text}, _location, stack) do
    [{tag_name, content} | stack] = stack
    [{tag_name, [:unicode.characters_to_binary(text) | content]} | stack]
  end

  def xml_event_fun({:endElement, _, tag_name, _}, _location, stack) do
    [{^tag_name, content} | stack] = stack
    element = {:unicode.characters_to_binary(tag_name), :lists.reverse(content)}

    # TODO content = [binary] -> binary
    # TODO content = [] -> drop

    case stack do
      [] -> element
      [{parent_name, parent_content} | rest] -> [{parent_name, [element | parent_content]} | rest]
    end
  end

  def xml_event_fun(:startDocument, _location, :undefined), do: _stack = []
  def xml_event_fun(:endDocument, _location, stack), do: stack
  def xml_event_fun(_event, _location, stack), do: stack
end
