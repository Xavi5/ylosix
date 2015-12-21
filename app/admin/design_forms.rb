ActiveAdmin.register DesignForm do
  menu parent: 'Design'

  permit_params do
    permitted = [:tag]

    locales = Language.pluck(:locale).map(&:to_sym)
    permitted << {content_translations: locales}
    permitted
  end

  index do
    selectable_column
    id_column

    column :tag

    actions
  end

  filter :tag

  form do |f|
    f.inputs 'Action form Details' do
      f.input :tag

      admin_translation_text_field(design_form, 'design_form', 'content_translations', component: ActiveAdminHelper::CK_EDITOR)
    end

    f.actions
  end
end
