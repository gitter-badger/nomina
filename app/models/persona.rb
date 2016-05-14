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

  def calculo
    inicio_mes=Date.civil($ahora.year,$ahora.month, 1)
    fin_mes= Date.civil($ahora.year,$ahora.month, -1)
    fecha=($quincena==0) ? Date.civil($ahora.year,$ahora.month, 15) : fin_mes
  sueldos= cargo.sueldos.where("created_at < ?",fecha)

    if !(sueldos.length > 0)
      self.valido=false
      return 0
    end
    self.valido=true
    @SUELDO = sueldos.last.monto
    @SUELDO_INTEGRAL = sueldos.last.sueldo_integral
    calc=Dentaku::Calculator.new
 lunes = [1]
 r = (inicio_mes..fin_mes).to_a.select {|k| lunes.include?(k.wday)}
    @LUNES_DEL_MES=r.length
    self.asignaciones = []
    self.deducciones = []
    self.total_asignaciones = 0
    self.total_deducciones = 0

    a = cargo.tipo.conceptos.where(tipo_de_concepto: 0)
    ap = registrosconceptos.joins(:conceptopersonal).where('"conceptospersonales"."tipo_de_concepto"= 0')
    d = cargo.tipo.conceptos.where(tipo_de_concepto: 1)
    dp = registrosconceptos.joins(:conceptopersonal).where('"conceptospersonales"."tipo_de_concepto"= 1')

    i = 0

    a.each do |j|
      next unless j.modalidad_de_pago == $quincena || j.modalidad_de_pago == 2
      f=j.formulas.where("created_at < ?",fecha)
      next unless f.length>0
      f=f.last
      valor = calc.evaluate(f.empleado, sueldo:@SUELDO,sueldo_integral:@SUELDO_INTEGRAL, lunes_del_mes:@LUNES_DEL_MES).to_d
      valor_patrono = calc.evaluate(f.patrono, sueldo:@SUELDO,sueldo_integral:@SUELDO_INTEGRAL, lunes_del_mes:@LUNES_DEL_MES).to_d
      self.total_asignaciones += valor
      asignaciones[i] = Hash['nombre', j.nombre, 'valor', (valor - 0.0005).round(2).to_s,'valor_patrono', (valor_patrono - 0.0005).round(2).to_s ]
      i += 1
    end
    ap.each do |j|
      aplicar = false
      case j.modalidad_de_pago
      when 0
        quincena = j.created_at.day <= 15 ? 0 :  1
        if quincena == $quincena && $ahora.month == j.created_at.month
          aplicar = true
        end
      when 1
        quincena = j.created_at.day <= 15 ? 0 : 1
        if quincena != $quincena && (j.created_at.month == $ahora.month || j.created_at.month == $ahora.month - 1)

          aplicar = true

        end
      when 2..4
        if j.modalidad_de_pago == $quincena + 2 || j.modalidad_de_pago == 4
          aplicar = true
        end

      end
      next unless aplicar == true
      f=j.formulaspersonales.where("created_at < ?",fecha)
      next unless f.length>0
      f=f.last

      valor = calc.evaluate(f.empleado, sueldo:@SUELDO,sueldo_integral:@SUELDO_INTEGRAL, lunes_del_mes:@LUNES_DEL_MES).to_d
      valor_patrono = calc.evaluate(f.patrono, sueldo:@SUELDO,sueldo_integral:@SUELDO_INTEGRAL, lunes_del_mes:@LUNES_DEL_MES).to_d
      self.total_asignaciones += valor
      asignaciones[i] = Hash['nombre', j.conceptopersonal.nombre, 'valor', (valor - 0.0005).round(2).to_s, 'valor_patrono', (valor_patrono - 0.0005).round(2).to_s ]
      i += 1
    end
    i = 0

    d.each do |j|
      next unless j.modalidad_de_pago == $quincena || j.modalidad_de_pago == 2
      aplicar = false
      case j.condicion

      when 0
        aplicar = true
      when 1
        aplicar = self.FAOV ? true : false
      when 2
        aplicar = self.IVSS ? true : false
      when 3
        aplicar = self.TSS ? true : false
      when 4
        aplicar = self.caja_de_ahorro ? true : false
      end
      next unless aplicar
      f=j.formulas.where("created_at < ?",fecha)
      next unless f.length>0
      f=f.last
      valor = calc.evaluate(f.empleado, sueldo:@SUELDO,sueldo_integral:@SUELDO_INTEGRAL, lunes_del_mes:@LUNES_DEL_MES).to_d
      valor_patrono = calc.evaluate(f.patrono, sueldo:@SUELDO,sueldo_integral:@SUELDO_INTEGRAL, lunes_del_mes:@LUNES_DEL_MES).to_d
      self.total_deducciones += valor
      deducciones[i] = Hash['nombre', j.nombre, 'valor', (valor - 0.0005).round(2).to_s ,'valor_patrono', (valor_patrono - 0.0005).round(2).to_s]
      i += 1
    end

    dp.each do |j|
      aplicar = false
      case j.modalidad_de_pago
      when 0
        quincena = j.created_at.day <= 15 ? 0 :  1
        if quincena == $quincena && $ahora.month == j.created_at.month
          aplicar = true
        end
      when 1
        quincena = j.created_at.day <= 15 ? 0 : 1
        if quincena != $quincena && (j.created_at.month == $ahora.month || j.created_at.month == $ahora.month - 1)

          aplicar = true
        end

      when 2..4
        if j.modalidad_de_pago == $quincena + 2 || j.modalidad_de_pago == 4
          aplicar = true
        end

      end
      next unless aplicar == true
      f=j.formulaspersonales.where("created_at < ?",fecha)
      next unless f.length>0
      f=f.last
      valor = calc.evaluate(f.empleado, sueldo:@SUELDO,sueldo_integral:@SUELDO_INTEGRAL, lunes_del_mes:@LUNES_DEL_MES).to_d
      valor_patrono = calc.evaluate(f.patrono, sueldo:@SUELDO,sueldo_integral:@SUELDO_INTEGRAL, lunes_del_mes:@LUNES_DEL_MES).to_d
      self.total_deducciones += valor
      deducciones[i] = Hash['nombre', j.conceptopersonal.nombre, 'valor', (valor - 0.0005).round(2).to_s,'valor_patrono', (valor_patrono - 0.0005).round(2).to_s]
      i += 1
    end

    tipo_de_contrato = contrato.tipo_de_contrato
    if tipo_de_contrato == 2
      deducciones[i] = Hash['nombre', 'COMISION DE SERVICIO', 'valor', (contrato.sueldo_externo - 0.0005).round(2).to_s]
      self.total_deducciones += contrato.sueldo_externo
    end
    self.total = self.total_asignaciones - self.total_deducciones
    self.total = 0 if tipo_de_contrato == 2 && total < 0
  end
end
