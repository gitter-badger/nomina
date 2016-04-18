class PersonasController < ApplicationController
  before_action :set_persona, only: [:show, :edit, :update, :destroy,:jubilarse]
  $dic = Hash['tipos_de_contrato' => Hash['Fijo' => 0, 'Temporal' => 1, 'Externo' => 2],
              'sexos' => Hash['Masculino' => 0, 'Femenino' => 1],
              'tipos_de_cedula' => Hash['V-' => 0, 'E-' => 1]]
  # GET /personas
  # GET /personas.json
  def index
    @personas = Persona.activo.order(:cedula).paginate(:per_page => 1, :page => params[:page])
    @personas_retiradas = Persona.retirado.order(:cedula).paginate(:per_page => 1, :page => params[:page])
  end

  # GET /personas/1
  # GET /personas/1.json
  def show
  end
  
  def jubilarse
    
    respond_to do |format|
      if @persona.retirar!
format.html { redirect_to @persona, notice: 'El empleado esta retirado' }
      format.json { head :no_content }
      else
        format.html { render :new }
        format.json { render json: @persona.errors, status:' elmpleado ya esta retirado.' }
      end
    end

  end

  # GET /personas/new
  def new
    @editable=true;
    if Cargo.where('disponible=true').length <= 0
      respond_to do |format|
        format.html { redirect_to personas_url, notice: 'No hay cargo disponibles.' }
        format.json { render json: @persona.errors, status: 'No hay cargos disponibles' }
      end
    else
      @persona = Persona.new
      @persona.contrato = Contrato.new
    end
  end

  # GET /personas/1/edit
  def edit
    @editable=false;
  end
  # POST /personas
  # POST /personas.json
  def create
    @persona = Persona.new(persona_params)

    respond_to do |format|
      if @persona.save
        @persona.cargo.disponible = false
        @persona.cargo.save
        #  Cargo.where(id: params[:cargo_id]).update_all(disponible: false);
        format.html { redirect_to @persona, notice: 'La persona fue contratada exitosamente.' }
        format.json { render :show, status: :created, location: @persona }
      else
        format.html { render :new }
        format.json { render json: @persona.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /personas/1
  # PATCH/PUT /personas/1.json
  def update
    respond_to do |format|
      if @persona.update(persona_params)
        format.html { redirect_to @persona, notice: 'Los datos del empleado fueron actualizados exitosamente.' }
        format.json { render :show, status: :ok, location: @persona }
      else
        format.html { render :edit }
        format.json { render json: @persona.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /personas/1
  # DELETE /personas/1.json
  def destroy
    @persona.cargo.update(disponible: true)
    @persona.destroy
    respond_to do |format|
      format.html { redirect_to personas_url, notice: 'El empleado fue despedido.' }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_persona
    @persona = Persona.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def persona_params
    params.require(:persona).permit(:cedula, :tipo_de_cedula, :cuenta,:FAOV, :TSS,:IVSS, :nombres, :apellidos, :telefono_fijo, :telefono_movil, :avatar, :fecha_de_nacimiento, :correo, :direccion, :sexo, :cargo_id, contrato_attributes: [:id, :tipo_de_contrato, :fecha_inicio, :fecha_fin, :sueldo_externo], familiares_attributes: [:id, :cedula, :nombres, :apellidos, :fecha_de_nacimiento, :sexo, :direccion, :_destroy])
  end
end
