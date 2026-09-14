# frozen_string_literal: true

class FilesHandler
  include Dummy::V1::Handlers::Files

  STORE = {}

  def download_mod_file(request:)
    body = STORE[request.path.mod_id]

    if body.nil?
      return Dummy::V1::Operations::DownloadModFile::NotFound.new(
        body: Dummy::V1::Types::ProblemDetails.new(title: "no file for mod #{request.path.mod_id}")
      )
    end

    Dummy::V1::Operations::DownloadModFile::Ok.new(body: body)
  end

  def upload_mod_file(request:)
    bytes = [
      request.body.upload.original_filename,
      request.body.description,
      request.body.upload.tempfile.read
    ].compact.join("|")

    STORE[request.path.mod_id] = Oapi::Body::Stream.new(body: ->(sink) { sink.write(bytes) })

    Dummy::V1::Operations::UploadModFile::NoContent.new
  end
end
