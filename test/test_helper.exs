ExUnit.start()

# Start the GenServer for tests only
{:ok, _pid} = PdfScreenplayParsex.PdfScreenplayServer.start_link()
