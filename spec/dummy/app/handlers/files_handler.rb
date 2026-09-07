# frozen_string_literal: true

class FilesHandler
  include Dummy::V1::Handlers::Files

  STORE = {}

  def download_mod_file(request:)
    stored = STORE[request.path.mod_id]

    if stored.nil?
      return Dummy::V1::Operations::DownloadModFile::NotFound.new(
        body: Dummy::V1::Types::ProblemDetails.new(title: "no file for mod #{request.path.mod_id}")
      )
    end

    Dummy::V1::Operations::DownloadModFile::Ok.new(body: StringIO.new(stored), chunk: 4)
  end

  def upload_mod_file(request:)
    STORE[request.path.mod_id] = [
      request.body.upload.original_filename,
      request.body.description,
      request.body.upload.tempfile.read
    ].compact.join("|")

    Dummy::V1::Operations::UploadModFile::NoContent.new
  end
end
