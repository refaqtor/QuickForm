require 'openstudio'
require 'json'

class OSModel < OpenStudio::Model::Model

  def add_geometry(coords, gridSize, floors, floorHeight, wwr)
  	
  	floor = 0
  	winH = floorHeight * wwr
  	wallH = (floorHeight - winH) / 2
  	bldgH = floors * floorHeight
  	wwrSub = (((winH - 0.05)* (gridSize - 0.05)) / (winH * gridSize)) - 0.01
  	puts winH
  	puts gridSize
  	puts wwrSub
  	num_surfaces = 0
    previous_num_surfaces = 0
    #Loop through Floors
    for floor in (0..floors -1)
    	z0 = floor *  floorHeight
    	z1 = z0 + wallH
    	z2 = z1 + winH
    	heights = [z0, z1, z2]
    	heights.each do |z|
    		if z == z0 || z ==z2
    			height = wallH
    		else
    			height = winH
    		end
    		osPoints = Array.new
    		#Create a new story within the building
    		story = OpenStudio::Model::BuildingStory.new(self)
    		story.setNominalFloortoFloorHeight(height)
    		story.setName("Story #{floor+1}")
    		#Loop Trough Sides
    		#loop through 3 iterations of sides

    		for i in (1..coords.length-1)
    		 points = createWallGrid(coords[i -1], coords[i], gridSize)
    		 points.pop
    		 points.each do |point|
    		 	osPoints.push(OpenStudio::Point3d.new(point[0], point[1], z))
    		 end
    		end
    		points = createWallGrid(coords[coords.length-1], coords[0], gridSize)
    		points.pop
    		points.each do |point|
	    		osPoints.push(OpenStudio::Point3d.new(point[0], point[1], z))
    		end
    	
    	
	    	# Identity matrix for setting space origins
	    	m = OpenStudio::Matrix.new(4,4,0)
	    	m[0,0] = 1
    		m[1,1] = 1
	    	m[2,2] = 1
    		m[3,3] = 1
    		# Minimal zones
    		core_polygon = OpenStudio::Point3dVector.new
    		osPoints.each do |point|
	    		core_polygon << point
	    	end
			core_space = OpenStudio::Model::Space::fromFloorPrint(core_polygon, height, self)
			core_space = core_space.get
    		m[0,3] = osPoints[0].x
    		m[1,3] = osPoints[0].y
    		m[2,3] = osPoints[0].z
    		core_space.changeTransformation(OpenStudio::Transformation.new(m))
	    	core_space.setBuildingStory(story)
    		core_space.setName("#{floor} Core Space")

    		#Set vertical story position
    		story.setNominalZCoordinate(z)

    	end # End of grid Loop
    	

    end #End of Floors Loop

    #Put all of the spaces in the model into a vector
    spaces = OpenStudio::Model::SpaceVector.new
    self.getSpaces.each { |space| spaces << space }

    #Match surfaces for each space in the vector
    OpenStudio::Model.matchSurfaces(spaces) # Match surfaces and sub-surfaces within spaces
    
    #Apply a thermal zone to each space in the model if that space has no thermal zone already
    self.getSpaces.each do |space|
      if space.thermalZone.empty?
        new_thermal_zone = OpenStudio::Model::ThermalZone.new(self)
        space.setThermalZone(new_thermal_zone)
      end
    end # end space loop
    
  end # end add_geometry method  


  def add_windows(coords, gridSize, floors, floorHeight, wwr, application_type)
  	#input checking

    if wwr <= 0 or wwr >= 1
      return false
    end

    heightOffsetFromFloor = nil
    if application_type == "Above Floor"
      heightOffsetFromFloor = true
    else
      heightOffsetFromFloor = false
    end
    winH = floorHeight * wwr
    wallH = (floorHeight - winH) / 2
    bldgH = floors * floorHeight
    wwrSub = (((winH - 0.05)* (gridSize - 0.05)) / (winH * gridSize)) - 0.01

    numb_patches = get_num_patches(coords, gridSize)
    puts "Number Patches #{numb_patches}"
    for floor in (0..floors -1)
        self.getSurfaces.each do |s|
            next if not s.outsideBoundaryCondition == "Outdoors"
            startNumb = numb_patches + 3 + (floor * ((numb_patches * 3) + 6))
            endNum = startNumb + numb_patches
            next if not s.name.to_s.split(" ")[1].to_i.between?(startNumb,endNum)
            #puts "start Numbers: #{startNumb}"
            #puts "End Numbers: #{endNum}"
            new_window = s.setWindowToWallRatio(wwrSub, 0.025, heightOffsetFromFloor)
        end
    end

  end # end add_windows method 
  def remove_extra_floors_ceilings()
    patches = self.getSurfaces.length
    numb_roofCelFloor = 0
    puts "Patches: #{patches}"
    self.getSurfaces.each do |s|
        next if s.name.to_s.split(" ")[1].to_i == 1 ||s.name.to_s.split(" ")[1].to_i == patches
        next if not s.surfaceType == "Floor" || s.surfaceType == "RoofCeiling"
        s.remove
    end
    puts OpenStudio::Model::Surface::validSurfaceTypeValues()
  end

  def create_roof_subsurfaces(floors, floorHeight)
    surfacePoints = OpenStudio::Point3dVector.new
    surfacePoints << OpenStudio::Point3d.new(0, -5, 1.005)
    surfacePoints << OpenStudio::Point3d.new(5, -5, 1.005)
    surfacePoints << OpenStudio::Point3d.new(5, 0, 1.005)
    surfacePoints << OpenStudio::Point3d.new(0, 0, 1.005)
    sub_surface = OpenStudio::Model::SubSurface.new(surfacePoints, self)
    patches = self.getSurfaces.length
    self.getSurfaces.each do |s|
        next if not s.name.to_s.split(" ")[1].to_i == 216
        puts "Roof Surface #{s.name}"
        sub_surface.setSurface(s)
        sub_surface.setSubSurfaceType("Door")
        puts OpenStudio::Model::SubSurface::validSubSurfaceTypeValues()
    end
  end

  def add_constructions(construction_library_path, degree_to_north)
	  
  
    #input error checking
    if not construction_library_path
      return false
    end
    #make sure the file exists on the filesystem; if it does, open it
    construction_library_path = OpenStudio::Path.new(construction_library_path)
    if OpenStudio::exists(construction_library_path)
      construction_library = OpenStudio::IdfFile::load(construction_library_path, "OpenStudio".to_IddFileType).get
    else
      puts "#{construction_library_path} couldn't be found"
    end

    #add the objects in the construction library to the model
    self.addObjects(construction_library.objects)
    
    #apply the newly-added construction set to the model
    building = self.getBuilding
    default_construction_set = OpenStudio::Model::getDefaultConstructionSets(self)[0]
    building.setDefaultConstructionSet(default_construction_set)
	building.setNorthAxis(degree_to_north)
  
  end #end Constructions

  def add_roof()

  end


  def set_runperiod(day, month)
    #From https://github.com/buildsci/openstudio_scripts/blob/master/newMethods/newMethods.rb
    runPeriod = self.getRunPeriod
    runPeriod.setEndDayOfMonth(day)
    runPeriod.setEndMonth(month)
  end

  

  def save_openstudio_osm(dir, name)
    save_path = OpenStudio::Path.new("#{dir}/#{name}")
    self.save(save_path,true)
    
  end
  
  def translate_to_energyplus_and_save_idf(dir,name)
  
    #make a forward translator and convert openstudio model to energyplus
    forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new()
    workspace = forward_translator.translateModel(self)
    idf_save_path = OpenStudio::Path.new("#{dir}/#{name}")
    workspace.save(idf_save_path,true)
  
  end

  def add_temperature_variable(dir, name)
  	# Open a file and read from it
	File.open("#{dir}#{name}.idf", 'a') {|f| f.write("Output:Variable,*,Surface Outside Face Temperature,hourly; !- Zone Average [C]\nOutput:Variable,*,Surface Outside Face Convection Heat Gain Rate,hourly; !- Zone Average [W]\nOutput:Variable,*,Surface Outside Face Convection Heat Gain Rate per Area,hourly; !- Zone Average [W/m2]\nOutput:Variable,*,Surface Outside Face Solar Radiation Heat Gain Rate,hourly; !- Zone Average [W]\nOutput:Variable,*,Surface Outside Face Solar Radiation Heat Gain Rate per Area,hourly; !- Zone Average [W/m2]\nOutput:Variable,*,Surface Outside Face Conduction Heat Loss Rate,hourly; !- Zone Average [W]\nOutput:Variable,*,Surface Outside Face Conduction Heat Transfer Rate per Area,hourly; !- Zone Average [W/m2]") }
  end

  def set_solarDist()
    simControl = self.getSimulationControl
    simControl.setSolarDistribution("FullExteriorWithReflections")
  end

end

def distanceFormula(x1,y1,x2,y2)
	return Math.sqrt(((x2-x1)*(x2-x1)) + ((y2-y1)*(y2-y1)))
end

#Do Grid for One Length

def get_num_patches(coords, gridSize)
    numb_patches = 0 
    orgGridSize = gridSize
    puts "iterators"
    for pt in (1..coords.length-1)
        gridSize = orgGridSize
        sideLength = distanceFormula(coords[pt-1][0],coords[pt-1][1],coords[pt][0],coords[pt][1])
        gridLength = ((sideLength % gridSize) / ((sideLength / gridSize).to_i)) + gridSize
        #Number of Grid Checks
        if (gridSize * 2) > sideLength
            gridLength = sideLength / 2
            gridSize = gridLength
        end
        iterator = (sideLength / gridSize).to_i
        numb_patches += iterator
    end
    gridSize = orgGridSize
    sideLength = distanceFormula(coords[coords.length-1][0],coords[coords.length-1][1],coords[0][0],coords[0][1])
    #Number of Grid Checks
    if (gridSize * 2) > sideLength
        gridLength = sideLength / 2
        gridSize = gridLength
    end
    iterator = (sideLength / gridSize).to_i
    numb_patches +=iterator  
    return numb_patches
end

def createWallGrid(point1, point2, gridSize)
	sideLength = distanceFormula(point1[0],point1[1],point2[0],point2[1])
	gridLength = ((sideLength % gridSize) / ((sideLength / gridSize).to_i)) + gridSize
	#Number of Grid Checks
    if (gridSize * 2) > sideLength
    	gridLength = sideLength / 2
    	gridSize = gridLength
    end
	#Deltas and Iterators
	deltaX = point2[0] - point1[0]
    deltaY = point2[1] - point1[1]
    xIt = deltaX / (sideLength / gridSize).to_i
    yIt = deltaY / (sideLength / gridSize).to_i
    iterator = (sideLength / gridSize).to_i
    #Infinity Check
    #Zero Check

    points = Array.new
    #Loop Wall
    for i in (0..iterator)
    	points[i] = [point1[0] + (xIt * i), point1[1] + (yIt * i)]
    end
    return points
end



=begin
coords = [[-10,10],[10,10], [10,-10], [-10,-10]]
gridSize = 5
floors = 4
floorHeight =3
wwr = 0.33
fileName = 'test'


#initialize and make OSModel

model = OSModel.new

model.add_geometry(coords, gridSize, floors, floorHeight, wwr)
model.add_windows(coords, gridSize, floors, floorHeight, wwr,"Above Floor")
model.add_constructions('./ASHRAE_90.1-2004_Construction.osm', 0)
model.remove_extra_floors_ceilings()
#model.create_roof_subsurfaces(floors, floorHeight)
model.save_openstudio_osm('./', fileName)
model.translate_to_energyplus_and_save_idf('./', fileName)
model.add_temperature_variable('./', fileName)
=end


