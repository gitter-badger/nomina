class Concepto < ActiveRecord::Base
has_and_belongs_to_many :tipos
validates :nombre, uniqueness: true, presence: true
validates :formula, presence: true
end
