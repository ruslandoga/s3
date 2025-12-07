defmodule S3 do
  @moduledoc "Small S3-compatible API request builder and stuff"

  # TODO hide access_key_id and secret_access_key from inspect / logs

  @type headers :: [{String.t(), String.t()}]

  @type option ::
          {:access_key_id, String.t()}
          | {:secret_access_key, String.t()}
          | {:url, URI.t() | :uri_string.uri_string() | :uri_string.uri_map()}
          | {:host, String.t()}
          | {:region, String.t()}
          | {:method, :get | :post | :head | :patch | :delete | :options | :put | String.t()}
          | {:path, String.t()}
          | {:query, Enumerable.t()}
          | {:headers, headers}
          # TODO | {:body, iodata | {:stream, Enumerable.t()}, :url} ?
          | {:body, iodata | {:stream, Enumerable.t()}}
          | {:utc_now, DateTime.t()}

  @doc "Builds URI, headers, body triplet to be used with HTTP clients."
  @spec build([option]) :: {URI.t(), headers, body :: iodata | Enumerable.t()}
  def build(options) do
    access_key_id = Keyword.fetch!(options, :access_key_id)
    secret_access_key = Keyword.fetch!(options, :secret_access_key)

    url =
      case Keyword.fetch!(options, :url) do
        url when is_binary(url) -> %{} = :uri_string.parse(url)
        %URI{} = uri -> Map.from_struct(uri)
        %{} = parsed -> parsed
      end

    url =
      case url do
        %{port: port} when is_integer(port) -> url
        %{scheme: "http"} -> Map.put(url, :port, 80)
        %{scheme: "https"} -> Map.put(url, :port, 443)
      end

    host = Keyword.get(options, :host)
    path = Keyword.get(options, :path) || "/"
    query = Keyword.get(options, :query) || %{}
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
      |> put_header("host", host || url[:authority] || url.host)
      |> put_header("x-amz-content-sha256", amz_content_sha256)
      |> put_header("x-amz-date", amz_date)
      |> Enum.sort_by(fn {k, _} -> k end)

    # TODO method() to ensure only valid atoms are allowed
    method = String.upcase(to_string(method))

    url_query = if q = url[:query], do: URI.decode_query(q), else: %{}

    query =
      Map.merge(url_query, query)
      |> Enum.sort_by(fn {k, _} -> k end)
      |> URI.encode_query()

    path =
      path
      |> String.split("/", trim: true)
      |> Enum.map(&:uri_string.quote/1)
      |> Enum.join("/")

    path =
      case Path.join(url[:path] || "/", path) do
        "/" <> _ = path -> path
        _ -> "/" <> path
      end

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
      with {:stream, stream} <- body do
        string_to_sign_prefix = [
          "AWS4-HMAC-SHA256-PAYLOAD",
          ?\n,
          amz_date,
          ?\n,
          scope,
          ?\n
        ]

        acc = %{
          prefix: IO.iodata_to_binary(string_to_sign_prefix),
          key: signing_key,
          signature: signature
        }

        {:stream, Stream.transform(stream, acc, &__MODULE__.streaming_chunk/2)}
      end

    url = Map.merge(url, %{query: query, path: path})
    {struct!(URI, url), headers, body}
  end

  @doc "Calculates V4 signature"
  @spec signature([option]) :: String.t()
  def signature(options) do
    secret_access_key = Keyword.fetch!(options, :secret_access_key)
    body = Keyword.fetch!(options, :body)
    region = Keyword.fetch!(options, :region)
    service = Keyword.get(options, :service, "s3")
    utc_now = Keyword.get(options, :utc_now) || DateTime.utc_now()
    amz_short_date = Calendar.strftime(utc_now, "%Y%m%d")

    signing_key =
      ["AWS4" | secret_access_key]
      |> hmac_sha256(amz_short_date)
      |> hmac_sha256(region)
      |> hmac_sha256(service)
      |> hmac_sha256("aws4_request")

    hex_hmac_sha256(signing_key, body)
  end

  @doc "Returns a presigned URL"
  @spec sign([option]) :: URI.t()
  def sign(options) do
    access_key_id = Keyword.fetch!(options, :access_key_id)
    secret_access_key = Keyword.fetch!(options, :secret_access_key)

    url =
      case Keyword.fetch!(options, :url) do
        url when is_binary(url) -> %{} = :uri_string.parse(url)
        %URI{} = uri -> Map.from_struct(uri)
        %{} = parsed -> parsed
      end

    host = Keyword.get(options, :host)
    path = Keyword.get(options, :path) || "/"
    query = Keyword.get(options, :query) || %{}
    region = Keyword.fetch!(options, :region)
    method = Keyword.fetch!(options, :method)
    headers = Keyword.get(options, :headers) || []

    # hidden options
    service = Keyword.get(options, :service, "s3")
    utc_now = Keyword.get(options, :utc_now) || DateTime.utc_now()

    # TODO method() to ensure only valid atoms are allowed
    method = String.upcase(to_string(method))

    amz_date = Calendar.strftime(utc_now, "%Y%m%dT%H%M%SZ")
    amz_short_date = String.slice(amz_date, 0, 8)
    scope = IO.iodata_to_binary([amz_short_date, ?/, region, ?/, service, ?/, "aws4_request"])

    headers =
      Enum.map(headers, fn {k, v} -> {String.downcase(k), v} end)
      |> put_header("host", host || url[:authority] || url.host)
      |> Enum.sort_by(fn {k, _} -> k end)

    path =
      path
      |> String.split("/", trim: true)
      |> Enum.map(&:uri_string.quote/1)
      |> Enum.join("/")

    path =
      case Path.join(url[:path] || "/", path) do
        "/" <> _ = path -> path
        _ -> "/" <> path
      end

    signed_headers =
      headers
      |> Enum.map(fn {k, _} -> k end)
      |> Enum.intersperse(?;)
      |> IO.iodata_to_binary()

    url_query = if q = url[:query], do: URI.decode_query(q), else: %{}
    query = Map.merge(url_query, query)

    query =
      Map.merge(
        %{
          "X-Amz-Algorithm" => "AWS4-HMAC-SHA256",
          "X-Amz-Credential" => "#{access_key_id}/#{scope}",
          "X-Amz-Date" => amz_date,
          "X-Amz-SignedHeaders" => signed_headers
        },
        query
      )

    query =
      query
      |> Enum.sort_by(fn {k, _} -> k end)
      |> URI.encode_query()

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
      "UNSIGNED-PAYLOAD"
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
    query = query <> "&X-Amz-Signature=" <> signature
    url = Map.merge(url, %{query: query, path: path})
    struct!(URI, url)
  end

  # https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-streaming.html#sigv4-chunked-body-definition
  @doc false
  @spec streaming_chunk(iodata, acc) :: {[iodata], acc}
        when acc: %{prefix: binary, key: binary, signature: String.t()}
  def streaming_chunk(chunk, acc) do
    %{
      prefix: string_to_sign_prefix,
      key: signing_key,
      signature: prev_signature
    } = acc

    string_to_sign = [
      string_to_sign_prefix,
      prev_signature,
      # hex_sha256("") =
      "\ne3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n",
      hex_sha256(chunk)
    ]

    signature = hex_hmac_sha256(signing_key, string_to_sign)

    signed_chunk = [
      chunk |> IO.iodata_length() |> Integer.to_string(16),
      ";chunk-signature=",
      signature,
      "\r\n",
      chunk,
      "\r\n"
    ]

    {[signed_chunk], %{acc | signature: signature}}
  end

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

  @type xml_element :: {String.t(), [xml_element() | String.t()]}

  @doc """
  Decodes XML binaries and encodes term to XML iodata.

  Examples:

      iex> xml("")
      ** (ArgumentError) Can't detect character encoding due to lack of indata

      iex> xml("<Hello></Hello>")
      {:ok, {"Hello", []}}

      iex> IO.iodata_to_binary(xml({"Hello", []}))
      "<Hello></Hello>"

      iex> xml(\"""
      ...> <book>
      ...>
      ...> <title> Learning Amazon Web Services </title>
      ...>
      ...> <author> Mark Wilkins </author>
      ...>
      ...> </book>
      ...> \""")
      {:ok, {"book", [{"title", [" Learning Amazon Web Services "]}, {"author", [" Mark Wilkins "]}]}}

      iex> IO.iodata_to_binary(xml({"book", [{"title", [" Learning Amazon Web Services "]}, {"author", [" Mark Wilkins "]}]}))
      "<book><title> Learning Amazon Web Services </title><author> Mark Wilkins </author></book>"

      iex> xml(\"""
      ...> <?xml version="1.0" encoding="UTF-8"?>
      ...> <俄语 լեզու="ռուսերեն">данные</俄语>
      ...> \""")
      {:ok, {"俄语", ["данные"]}}

      iex> IO.iodata_to_binary(xml({"俄语", ["данные"]}))
      "<俄语>данные</俄语>"

  """
  @spec xml(binary) :: {:ok, xml_element} | {:error, any}
  def xml(xml) when is_binary(xml) do
    # TODO
    # See: https://elixirforum.com/t/utf-8-issue-with-erlang-xmerl-scan-function/1668/9
    # xml = :erlang.binary_to_list(xml)

    xml = String.trim(xml)

    result =
      :xmerl_sax_parser.stream(xml,
        event_fun: &__MODULE__.xml_event_fun/3,
        external_entities: :none
      )

    case result do
      {:ok, xml, ""} -> {:ok, xml}
      {:fatal_error, _, reason, _, _} -> raise ArgumentError, List.to_string(reason)
    end
  end

  # TODO
  @spec xml(xml_element) :: iodata
  def xml({name, content}) do
    [?<, name, ?>, xml_continue(content), "</", name, ?>]
  end

  defp xml_continue({name, content}) do
    [?<, name, ?>, xml_continue(content), "</", name, ?>]
  end

  defp xml_continue([{name, content} | rest]) do
    [?<, name, ?>, xml_continue(content), "</", name, ?> | xml_continue(rest)]
  end

  defp xml_continue([binary | rest]) when is_binary(binary) do
    [xml_escape(binary) | xml_continue(rest)]
  end

  defp xml_continue([atom | rest]) when is_atom(atom) do
    [atom |> Atom.to_string() |> xml_escape() | xml_continue(rest)]
  end

  defp xml_continue([number | rest]) when is_number(number) do
    [to_string(number) | xml_continue(rest)]
  end

  defp xml_continue([] = empty), do: empty

  # TODO speed-up
  defp xml_escape(binary) do
    binary
    |> String.replace("<", "&lt;")
    |> String.replace("&", "&amp;")
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
