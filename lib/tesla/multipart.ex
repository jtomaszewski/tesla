defmodule Tesla.Multipart do
  @moduledoc """
  Multipart functionality.

  ### Example
  ```
  mp =
    Multipart.new
    |> Multipart.add_content_type_param("charset=utf-8")
    |> Multipart.add_field("field1", "foo")
    |> Multipart.add_field("field2", "bar", headers: [{:"Content-Id", 1}, {:"Content-Type", "text/plain"}])
    |> Multipart.add_file("test/tesla/multipart_test_file.sh")
    |> Multipart.add_file("test/tesla/multipart_test_file.sh", name: "foobar")
    |> Multipart.add_file_content("sample file content", "sample.txt")

    response = client.post(url, mp)
 ```
  """

  @boundary_chars "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" |> String.split("")

  @type part_stream :: IO.Stream.t | File.Stream.t
  @type part_value :: String.t | part_stream

  defstruct [
    parts: [],
    boundary: nil,
    content_type_params: []
  ]

  @type t :: %__MODULE__ {
    parts: list(Part.t),
    boundary: String.t,
    content_type_params: [String.t]
  }

  defmodule Part do
    @moduledoc false

    defstruct [
      body: nil,
      dispositions: [],
      headers: [],
    ]

    @type t :: %__MODULE__ {
      body: String.t,
      headers: Keyword.t,
      dispositions: Keyword.t,
    }
  end

  @doc """
  Create a new Multipart struct to be used for a request body.
  """
  @spec new() :: t
  def new do
    %__MODULE__{boundary: unique_string(32)}
  end

  @doc """
  Add a parameter to the multipart content-type.
  """
  @spec add_content_type_param(t, String.t) :: t
  def add_content_type_param(%__MODULE__{} = mp, param) do
    %{mp | content_type_params: mp.content_type_params ++ [param]}
  end

  @doc """
  Add a field part.
  """
  @spec add_field(t, String.t, part_value, Keyword.t) :: t
  def add_field(%__MODULE__{} = mp, name, value, opts \\ []) do
    {headers, opts} = Keyword.pop_first(opts, :headers, [])

    part = %Part{
      body: value,
      headers: headers,
      dispositions: [{:name, name}] ++ opts
    }
    %{mp | parts: mp.parts ++ [part]}
  end

  @doc """
  Add a file part. The file will be streamed.

  Options:
  - `:name` - name of form param
  - `:filename` - filename (defaults to path basename)
  - `:headers` - additional headers
  """
  @spec add_file(t, String.t, Keyword.t) :: t
  def add_file(%__MODULE__{} = mp, path, opts \\ []) do
    data = File.stream!(path, [:read], 2048)
    {filename, opts}  = Keyword.pop_first(opts, :filename, Path.basename(path))
    add_file_content(mp, data, filename, opts)
  end


  @doc """
  Add a file part. Same of `add_file/3` but the file content is read from `data` input parameter.
  """
  @spec add_file_content(t, part_value, String.t, Keyword.t) :: t
  def add_file_content(%__MODULE__{} = mp, data, filename, opts \\ []) do
    {name, opts} = Keyword.pop_first(opts, :name, "file")
    {headers, opts} = Keyword.pop_first(opts, :headers, [])
    {detect_content_type, opts} = Keyword.pop_first(opts, :detect_content_type, false)

    # add in detected content-type if necessary
    headers = case detect_content_type do
                true -> Keyword.put(headers, :"Content-Type", MIME.from_path(path))
                false -> headers
              end

    opts = opts ++ [filename: filename, headers: headers]

    add_field(mp, name, data, opts)
  end

  @doc false
  @spec headers(t) :: Keyword.t
  def headers(%__MODULE__{boundary: boundary, content_type_params: params}) do
    ct_params = (["boundary=#{boundary}"] ++ params) |> Enum.join("; ")
    [{:"Content-Type", "multipart/form-data; #{ct_params}"}]
  end

  @doc false
  @spec body(t) :: part_stream
  def body(%__MODULE__{boundary: boundary, parts: parts}) do
    part_streams = Enum.map(parts, &(part_as_stream(&1, boundary)))
    Stream.concat(part_streams ++ [["--#{boundary}--\r\n"]])
  end

  @doc false
  @spec part_as_stream(t, String.t) :: part_stream
  def part_as_stream(%Part{body: body, dispositions: dispositions, headers: part_headers}, boundary) do
    part_headers = Enum.map(part_headers, fn {k, v} -> "#{k}: #{v}\r\n" end)
    part_headers = part_headers ++ [part_headers_for_disposition(dispositions)]

    enum_body = case body do
                  b when is_binary(b)-> [b]
                  b -> b
                end

    Stream.concat([
      ["--#{boundary}\r\n"],
      part_headers,
      ["\r\n"],
      enum_body,
      ["\r\n"]
    ])
  end

  @doc false
  @spec part_headers_for_disposition(Keyword.t) :: [String.t]
  def part_headers_for_disposition([]), do: []
  def part_headers_for_disposition(kvs) do
    ds =
      kvs
      |> Enum.map(fn {k, v} -> "#{k}=\"#{v}\"" end)
      |> Enum.join("; ")
    ["Content-Disposition: form-data; #{ds}\r\n"]
  end

  @doc false
  @spec unique_string(pos_integer) :: String.t
  defp unique_string(length) do
    Enum.reduce((1..length), [], fn (_i, acc) ->
      [Enum.random(@boundary_chars) | acc]
    end) |> Enum.join("")
  end
end
