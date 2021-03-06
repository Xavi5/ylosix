# == Schema Information
#
# Table name: commerces
#
#  billing_address           :hstore           default({}), not null
#  created_at                :datetime         not null
#  default                   :boolean
#  enable_commerce_options   :boolean          default(FALSE), not null
#  ga_account_id             :string
#  http                      :string
#  id                        :integer          not null, primary key
#  language_id               :integer
#  logo_content_type         :string
#  logo_file_name            :string
#  logo_file_size            :integer
#  logo_updated_at           :datetime
#  meta_tags                 :hstore           default({}), not null
#  name                      :string
#  no_redirect_shopping_cart :boolean          default(FALSE), not null
#  order_prefix              :string           default(""), not null
#  per_page                  :integer          default(20)
#  social_networks           :hstore           default({}), not null
#  template_id               :integer
#  tree_category_id          :integer
#  updated_at                :datetime         not null
#
# Indexes
#
#  index_commerces_on_default           (default)
#  index_commerces_on_default_and_http  (default,http)
#  index_commerces_on_http              (http)
#  index_commerces_on_template_id       (template_id)
#
# Foreign Keys
#
#  fk_rails_f6f5a5f253  (template_id => templates.id)
#

class Commerce < ActiveRecord::Base
  include MetaTags

  belongs_to :template
  belongs_to :language
  belongs_to :tree_category, class_name: 'Category', foreign_key: 'tree_category_id'

  has_many :shopping_orders

  has_attached_file :logo, styles: {original: '300x100'}

  validates_attachment_size :logo, less_than: 2.megabytes
  validates_attachment_content_type :logo, content_type: %r{\Aimage/.*\Z}

  store_accessor :billing_address, :name, :address_1, :address_2, :postal_code,
                 :city, :country, :phone, :cif, :email

  default_scope { includes(:template) }

  def self.retrieve(http)
    # t = Commerce.arel_table
    # commerce = Commerce.where(t[:http].eq(http).or(t[:default].eq(true))).take

    commerce = Commerce.find_by(http: http)
    commerce = Commerce.find_by(default: true) if commerce.nil?
    commerce = Commerce.new if commerce.nil?

    commerce
  end

  def to_liquid(_options = {})
    image_src = 'http://placehold.it/300x100'
    image_src = logo.url(:original) if logo?

    template_liquid = nil
    template_liquid = template.to_liquid unless template.blank?

    {
        'http' => http,
        'image_src' => image_src,
        'name' => name,
        'billing_address' => billing_address,
        'root_href' => Routes.root_path,
        'template' => template_liquid,
        'ga_account_id' => ga_account_id,
        'order_prefix' => order_prefix,
        'social_networks' => social_networks
    }
  end
end
