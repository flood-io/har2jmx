require 'sinatra'
require 'json'
require 'recursive-open-struct'
require 'ruby-jmeter'
require 'byebug'

get '/' do
  haml :index
end

post '/har2jmx' do
  convert
end

error 400 do
  'client error'
end

def convert
  if params[:har] && params[:har].empty?
    400
  else
    json = JSON.parse(params[:har])

    if json
      har = RecursiveOpenStruct.new(json, recurse_over_arrays: true)

      file = Tempfile.new('foo')

      generate_test_plan(har, file)

      file.rewind

      send_data file.read, filename: 'test.jmx'
    else
      400
    end
  end
end

def generate_test_plan(har, file)
  test do
    cache

    cookies

    header [
      { name: 'Accept-Encoding', value: 'gzip,deflate,sdch' },
      { name: 'Accept', value: 'text/javascript, text/html, application/xml, text/xml, */*' }
    ]

    threads count: 1 do
      # byebug
      har.log && har.log.entries && har.log.entries.map(&:pageref).uniq.each do |page|
        transaction name: page do
          har.log.entries.select { |request| request.pageref == page }.each do |entry|
            next unless entry.request.url =~ /http/
            params = entry.request.postData &&
              entry.request.postData.params &&
              entry.request.postData.params.any? &&
              entry.request.postData.params.map { |param| [param.name, param.value] }.flatten

            if params
              public_send entry.request.to_h.values.first.to_s.downcase, entry.request.url, fill_in: Hash[*params] do
                with_xhr if entry.request.headers.to_s =~ /XMLHttpRequest/
              end
            end

            if entry.request.postData && entry.request.postData.text
              method = entry.request.to_h.values.first.try(:downcase)
              method = 'post' if method == 'connect'
              if method
                public_send(method,
                  entry.request.url,
                  raw_body: entry.request.postData.text) do
                  with_xhr if entry.request.headers.to_s =~ /XMLHttpRequest/
                end
              end
            else
              method = entry.request.to_h.values.first.try(:downcase)
              if method
                public_send(method, entry.request.url) do
                  with_xhr if entry.request.headers.to_s =~ /XMLHttpRequest/
                end
              end
            end
          end
        end
      end
    end
  end.jmx(file: file.path)
end
