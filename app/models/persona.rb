class Persona < ActiveRecord::Base
  resourcify
  self.per_page = 10
  attr_readonly :cedula
  include AASM
  aasm column: 'status' do
    state :activo, initial: true
    state :suspendido
    state :retirado
    event :retirar do
      transitions from: :activo, to: :retirado
      after do
        cargo.disponible = true
        cargo.save
      end
    end
    event :reingresar do
      transitions from: :retirado, to: :activo
      after do
        cargo.disponible = false
        cargo.save
      end
    end

    event :suspender do
      transitions from: :activo, to: :suspendido
    end
    event :reactivar do
      transitions from: :suspendido, to: :activo
    end
  end
  belongs_to :cargo
  has_one :contrato, dependent: :destroy
  has_many :familiares, dependent: :destroy
  has_many :registrosconceptos, dependent: :destroy
  accepts_nested_attributes_for :contrato, :familiares, :registrosconceptos, reject_if: :all_blank, allow_destroy: true
  has_attached_file :avatar, styles: { medium: '300x300>', thumb: '100x100>' }, default_url: '/assets/missing.png'
  VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i
  validates_attachment_content_type :avatar, content_type: /\Aimage\/.*\Z/
  attr_readonly :tipo_de_cedula, :cedula
  validates :tipo_de_cedula, :cedula, :nombres, :apellidos, :correo, :fecha_de_nacimiento, :sexo, :cargo, :cuenta, :direccion, presence: true
  validates :correo, uniqueness: { case_sensitive: false, message: 'El correo ingresado ya existe.' }, format: { with: VALID_EMAIL_REGEX, message: 'El formato del correo es invalido' }
  validates :cedula, uniqueness: { case_sensitive: false, message: 'ya esta registrada.' }, numericality: { only_integer: true }
  validates :nombres, :apellidos, length: { in: 0..50 }
  validates :cuenta, numericality: { only_integer: true }
  validates :telefono_fijo, :telefono_movil, length: { is: 11 }, allow_blank: true, numericality: { only_integer: true }
  validates :cuenta, length: { is: 20 }
  validates :fecha_de_nacimiento, date: { before: proc { Time.now - 18.year }, message: 'es invalida. La persona debe ser mayor de edad.' }

  attr_accessor :asignaciones, :deducciones, :total, :total_asignaciones, :total_deducciones, :valido

  def truncar(n)
  return ("%0.2f" % n).to_f
  end

  def self.search(search, dep, tipo)
    search = search.downcase
    #sin filtro
    if dep == '' && search == '' && tipo==''
      order(:cedula)
      #solo departaent
    elsif dep && dep != '' && search == '' && tipo==''
      joins(:cargo).where('"cargos"."departamento_id" = CAST(? AS INTEGER)', dep).order(:cedula)
      #solo tipo
    elsif tipo && tipo != '' && search == '' && dep==''
      joins(:cargo).where('"cargos"."tipo_id" = CAST(? AS INTEGER)', tipo).order(:cedula)
      #tipo y depatamento
    elsif tipo && tipo != '' && search == '' and dep && dep != ''
      joins(:cargo).where('"cargos"."tipo_id" = CAST(? AS INTEGER) AND "cargos"."departamento_id" = CAST(? AS INTEGER) ', tipo,dep).order(:cedula)
      #departamento y busqueda
    elsif dep && dep != '' and search && search != '' and tipo==''
      joins(:cargo).where('(cedula LIKE ? OR LOWER(nombres) LIKE ? OR LOWER(apellidos) LIKE ? OR CONCAT(LOWER(nombres), \' \', LOWER(apellidos)) LIKE ?) AND "cargos"."departamento_id" = CAST(? AS INTEGER)', "%#{search}%", "%#{search}%", "%#{search}%", "%#{search}%", dep).order(:cedula)
      #tipo y busqueda
    elsif tipo && tipo != '' and search && search != '' and dep==''
      joins(:cargo).where('(cedula LIKE ? OR LOWER(nombres) LIKE ? OR LOWER(apellidos) LIKE ? OR CONCAT(LOWER(nombres), \' \', LOWER(apellidos)) LIKE ?) AND "cargos"."tipo_id" = CAST(? AS INTEGER)', "%#{search}%", "%#{search}%", "%#{search}%", "%#{search}%", tipo).order(:cedula)
      #tipo departamento y busqueda
    elsif tipo && tipo != '' and dep && dep != '' and search && search != ''
      joins(:cargo).where('(cedula LIKE ? OR LOWER(nombres) LIKE ? OR LOWER(apellidos) LIKE ? OR CONCAT(LOWER(nombres), \' \', LOWER(apellidos)) LIKE ?) AND "cargos"."departamento_id" = CAST(? AS INTEGER) AND "cargos"."tipo_id" = CAST(? AS INTEGER)', "%#{search}%", "%#{search}%", "%#{search}%", "%#{search}%", dep,tipo).order(:cedula)
#solo busqueda
    elsif search && search != ''
      where('cedula LIKE ? OR LOWER(nombres) LIKE ? OR LOWER(apellidos) LIKE ? OR CONCAT(LOWER(nombres), \' \', LOWER(apellidos)) LIKE ? ', "%#{search}%", "%#{search}%", "%#{search}%", "%#{search}%").order(:cedula)
    end
  end

  def calculo extras
    self.asignaciones = []
    self.deducciones = []
    self.total_asignaciones = 0
    self.total_deducciones = 0
    self.total=0
    self.valido=true
    lunes = [1]

    inicio_mes=Date.civil($ahora.year,$ahora.month, 1)
    fin_mes= Date.civil($ahora.year,$ahora.month, -1)
    fecha=($quincena==0) ? Date.civil($ahora.year,$ahora.month, 16) : fin_mes

  sueldos= cargo.sueldos.where("created_at <= ? ",fecha)

    if sueldos.length == 0

      self.valido=false
      return 0
    end
    r = (inicio_mes..fin_mes).to_a.select {|k| lunes.include?(k.wday)}

    @SUELDO = sueldos.last.monto
    @SUELDO_INTEGRAL = sueldos.last.sueldo_integral
    @LUNES_DEL_MES=r.length
    @CONDICIONES= [self.IVSS, self.FAOV, self.TSS, self.caja_de_ahorro, extras]
    asig = [cargo.tipo.conceptos.where(tipo_de_concepto: 0),registrosconceptos.joins(:conceptopersonal).where('"conceptospersonales"."tipo_de_concepto"= 0')]

    dedu = [cargo.tipo.conceptos.where(tipo_de_concepto: 1),registrosconceptos.joins(:conceptopersonal).where('"conceptospersonales"."tipo_de_concepto"= 1')]

    i = 0
asig.each do |a|
    a.each do |j|
      next unless j.puede_aplicar  @CONDICIONES
      j.calcular fecha, @SUELDO, @SUELDO_INTEGRAL,@LUNES_DEL_MES
      next unless j.valido
      self.total_asignaciones += j.valor
      asignaciones[i] = j.para_mostrar
      i += 1
    end
  end
    i = 0
 dedu.each  do |d|
    d.each do |j|
      next unless j.puede_aplicar @CONDICIONES
      j.calcular fecha, @SUELDO, @SUELDO_INTEGRAL,@LUNES_DEL_MES
      next unless j.valido
      self.total_deducciones += j.valor
      deducciones[i] = j.para_mostrar
      i += 1
    end
 end
    tipo_de_contrato = contrato.tipo_de_contrato
    if tipo_de_contrato == 2
      deducciones[i] = Hash['nombre', 'COMISION DE SERVICIO', 'valor', truncar(contrato.sueldo_externo).to_s]
      self.total_deducciones += contrato.sueldo_externo
    end
    self.total_deducciones=truncar(self.total_deducciones)
    self.total_asignaciones=truncar(self.total_asignaciones)
    self.total = truncar(self.total_asignaciones - self.total_deducciones)
    self.total = 0 if tipo_de_contrato == 2 && total < 0
  end
end
