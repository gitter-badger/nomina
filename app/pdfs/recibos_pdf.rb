class RecibosPdf < Prawn::Document
    def truncar(n)
        ('%0.2f' % n).to_f
    end

    def initialize(tipo, eco, con, conper)
        super(left_margin: 50)
        banner = 'app/assets/images/banner.png'
        if eco == 1
            font 'public/fonts/eco.ttf'
            banner = 'app/assets/images/banner_bn.png'
        end
        @cargos = tipo.cargos
        @cargos.each do |s|
            next unless s.disponible == false
            p = s.persona
            conperExtra = ''
            conExtra = ''
            total=0
            total_deducciones=0
            total_asignaciones=0
            if conper && conper != "0" && conper != ''
                conperExtra = Conceptopersonal.find(conper)
            end
            if con && con != "0" && con != ''
                conExtra = Concepto.find(con)
            end
            if con || conper
                p.calculo true
            else

                p.calculo false
            end
            next unless p.valido == true
            next unless p.status != 'retirado'
            # next unless (p.status != "suspendido")
            next unless (p.contrato.tipo_de_contrato != 2) || (p.total > 0 && p.contrato.tipo_de_contrato == 2)
            image banner, scale: 0.54, align: :center
            move_down 30
            text 'NOMINA PERSONAL ' + p.cargo.tipo.nombre.upcase, align: :center, size: 16
            text $dic['quincena'].key($quincena).upcase + 'DE ' + $dic['meses'].key($ahora.month) + $ahora.strftime(' DE %Y'), align: :center, size: 18
            table([["CEDULA: #{p.cedula}", "NOMBRES: #{p.nombres},#{p.apellidos}", "FECHA DE INGRESO: #{p.contrato.fecha_inicio}"]], cell_style: { border_width: 0, size: 10 }, header: true)
            table([["CARGO: #{p.cargo.nombre.upcase}", "BANCO DE VENEZUELA #{p.cuenta}", "SUEDO BASICO: #{p.cargo.sueldos.last.monto}"]], cell_style: { border_width: 0, size: 10 }, header: true)
            table([['UBICACION: SEDE FUNSONE']], cell_style: { border_width: 0, size: 10 })
            move_down 20
            data = [%w(CONCEPTO ASIGNACION DEDUCCION TOTAL)]

            p.asignaciones.each do |c|
              condicion1=false
              condicion2 =false
              if con && con != "0" && con != ''
condicion1=(c['nombre'] == conExtra.nombre)
              end
              if conper && conper != "0" && conper != ''
condicion2=(c['nombre'] == conperExtra.nombre)
              end
                next unless  condicion1|| condicion2 ||(!con and !conper)

                data += [[c['nombre'].upcase, c['valor'], '', '']]
                total_asignaciones+=c['valor'].to_f
            end
            p.deducciones.each do |c|
              condicion1=false
              condicion2 =false
              if con && con != "0" && con != ''
condicion1=(c['nombre'] == conExtra.nombre)
              end
              if conper && conper != "0" && conper != ''
condicion2=(c['nombre'] == conperExtra.nombre)
              end
                next unless  condicion1|| condicion2 ||(!con and !conper)
                data += [[c['nombre'].upcase, '', c['valor'], '']]
                total_deducciones+=c['valor'].to_f
            end
            data += [['', truncar(total_asignaciones).to_s, truncar(total_deducciones).to_s, truncar(total_asignaciones-total_deducciones).to_s]]

            table(data, header: true, width: 500, cell_style: { size: 10 })
            start_new_page
        end
    end
end
