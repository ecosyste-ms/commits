module ApplicationHelper
  include Pagy::Frontend

  def meta_title
    [@meta_title, 'Ecosyste.ms: Commits'].compact.join(' | ')
  end

  def meta_description
    @meta_description || 'An open API service providing commit metadata for open source projects.'
  end

  def obfusticate_email(email)
    return unless email    
    email.split('@').map do |part|
      begin
        part.tap { |p| p[1...-1] = "****" }
      rescue
        '****'
      end
    end.join('@')
  end
end
