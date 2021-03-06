class GuideSection < ActiveRecord::Base
  attr_accessible :description, :guide_taxon_id, :title, :position, :rights_holder, :license, :source_id, :source_url, :modified_on_create
  attr_accessor :modified_on_create
  belongs_to :guide_taxon, :inverse_of => :guide_sections
  has_one :guide, :through => :guide_taxon
  before_create :set_license
  after_create :touch_if_modified
  after_save {|r| r.guide.expire_caches(:check_ngz => true)}
  after_destroy {|r| r.guide.expire_caches(:check_ngz => true)}

  validates_length_of :title, :within => 1..256

  EOL_SUBJECTS = %w(
    Associations
    Barcode
    Behaviour
    Biology
    CitizenScience
    Conservation
    ConservationStatus
    Cyclicity
    Cytology
    Description
    Development
    DiagnosticDescription
    Diseases
    Dispersal
    Distribution
    Ecology
    Education
    EducationResources
    Evolution
    FossilHistory
    FunctionalAdaptations
    GeneralDescription
    Genetics
    Genome
    Growth
    Habitat
    IdentificationResources
    Key
    Legislation
    LifeCycle
    LifeExpectancy
    LookAlikes
    Management
    Migration
    MolecularBiology
    Morphology
    Notes
    NucleotideSequences
    Physiology
    PopulationBiology
    Procedures
    Reproduction
    RiskStatement
    Size
    SystematicsOrPhylogenetics
    TaxonBiology
    Taxonomy
    Threats
    Trends
    TrophicStrategy
    TypeInformation
    Use
  )

  def to_s
    "<GuideSection #{id}>"
  end

  def attribution
    if adapted?
      I18n.t :adapted_by_name_from_a_work_by_original, :name => guide.user.name, :original => original_attribution
    else
      original_attribution
    end
  end

  def original_attribution
    @original_attribution ||= if license == Photo::PD_CODE
      I18n.t('copyright.public_domain', :default => "public domain").titleize
    elsif license.blank?
      I18n.t('copyright.all_rights_reserved', :name => attribution_name)
    else
      I18n.t('copyright.some_rights_reserved_by', :name => attribution_name, :license_short => license.sub('-', ' '))
    end
  end

  def attribution_name
    rights_holder_name ||= rights_holder unless rights_holder.blank?
    if guide && source_url.blank?
      rights_holder_name ||= guide.user.name unless guide.user.name.blank?
      rights_holder_name ||= guide.user.login
    end
    rights_holder_name ||= I18n.t(:unknown)
  end

  def set_license
    return true if !license.blank?
    self.license = guide.try(:license)
    true
  end

  def editable?
    license.blank? || ![Photo::CC_BY_ND, Photo::CC_BY_NC_ND].include?(license)
  end

  def modified?
    return false unless updated_at && created_at
    updated_at > created_at
  end

  def adapted?
    modified? && original_attribution !~ /#{guide.user.name}/
  end

  def touch_if_modified
    touch if modified_on_create == true || modified_on_create == "true"
  end

  def self.new_from_eol_data_object(data_object)
    gs = GuideSection.new(
      :title => (data_object.at('title') || data_object.at('subject')).content.split('#').last.underscore.humanize,
      :description => data_object.at('description').try(:content),
      :rights_holder => data_object.at('rightsHolder').try(:content) || data_object.at('agent[role=compiler]').try(:content)
    )
    gs.license = case data_object.at('license').to_s
    when /\/by\// then Observation::CC_BY
    when /\/by-nc\// then Observation::CC_BY_NC
    when /\/by-sa\// then Observation::CC_BY_SA
    when /\/by-nd\// then Observation::CC_BY_ND
    when /\/by-nc-sa\// then Observation::CC_BY_NC_SA
    when /\/by-nc-nd\// then Observation::CC_BY_NC_ND
    when /\/publicdomain\// then Photo::PD_CODE
    else
      data_object.at('license').to_s
    end
    gs.source_url = if (verson_id = data_object.at('dataObjectVersionID').try(:content))
      "http://eol.org/data_objects/#{verson_id}"
    elsif data_object.at('source').to_s =~ /http/
      data_object.at('source').to_s
    end
    gs
  end
end
