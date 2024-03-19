module BlacklightOaiProvider
  class SolrDocumentProvider < ::OAI::Provider::Base
    attr_accessor :options

    PROVIDER_INSTANCE_ATTRS = {
      name: :repository_name,
      url: :repository_url,
      prefix: :record_prefix,
      email: :admin_email,
      delete_support: :deletion_support,
      granularity: :update_granularity,
      model: :source_model,
      identifier: :sample_id,
      description: :extra_description
    }.freeze

    def initialize(controller, options = {})
      super(options.merge(provider_context: :instance_based))

      provider_options = convert_to_instance_options(options.fetch(:provider, {}))
      provider_options[:granularity] ||= OAI::Const::Granularity::HIGH
      wrapper_options = options.fetch(:document, {}).dup.merge(granularity: provider_options[:granularity])
      provider_options[:model] ||= SolrDocumentWrapper.new(controller, wrapper_options)
      provider_options[:name] ||= controller.view_context.application_name
      provider_options[:url] ||= controller.view_context.oai_catalog_url
      provider_options.each do |k, v|
        v = v.call(controller) if v.is_a?(Proc)
        send :"#{k}=", v
      end

      @supported_formats = options.dig(:document, :supported_formats)
      @supported_formats = ['oai_dc'] if @supported_formats.blank?
    end

    def process_request(params = {})
      begin
        validate_metadata_format(params[:verb], params[:metadataPrefix]) if params[:resumptionToken].blank?
        validate_granularity(params[:from], params[:until]) if params[:from] && params[:until]
        params[:from] = parse_date(params[:from]) if params[:from]
        params[:until] = parse_date(params[:until]) if params[:until]
      rescue => err
        return OAI::Provider::Response::Error.new(self.class, err).to_xml
      end

      super params
    end

    def list_sets(options = {})
      BlacklightOaiProvider::Response::ListSets.new(self, options).to_xml
    end

    def convert_to_instance_options(controller_options)
      instance_options = controller_options.dup
      PROVIDER_INSTANCE_ATTRS.each { |inst_att, class_att| instance_options[inst_att] ||= instance_options.delete(class_att) }
      instance_options.delete_if { |k, _v| PROVIDER_INSTANCE_ATTRS[k].nil? }
      instance_options
    end

    def validate_granularity(from, to)
      raise(OAI::ArgumentException.new, "Date granularities do not match! #{from} - #{to}") unless from.length == to.length
    end

    def validate_metadata_format(verb, metadata_prefix)
      if ['ListIdentifiers', 'ListRecords', 'GetRecord'].include? verb
        raise(OAI::ArgumentException.new, "metadataPrefix not provided") if metadata_prefix.blank?
        return metadata_prefix if @supported_formats.include? metadata_prefix
        raise(OAI::FormatException.new, "metadataPrefix not supported")
      end
    end
  end
end
