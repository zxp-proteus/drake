function model=addRobotFromSDF(model,sdf_filename,xyz,rpy,options)
% Parses SDF and/or Gazebo WORLD file
% The spec is here: http://sdformat.org/spec
% A nice trove of models is here: https://bitbucket.org/osrf/gazebo_models/
%
% @param sdf_filename filename of file to parse
%
% @options floating boolean where true means that a floating joint is
% automatically added to the root. @default false
% @options inertial boolean where true means parse dynamics parameters,
% false means skip them. @default true
% @options visual boolean where true means parse graphics parameters, false
% means skip them. @default true
% Useful for extracting the 2D geometries later. @default false
% @ingroup SDF Parsing

if (nargin<3 || isempty(xyz)), xyz = zeros(3,1); end
if (nargin<4 || isempty(rpy)), rpy = zeros(3,1); end

if (nargin<5), options = struct(); end
if (~isfield(options,'floating')), options.floating = ''; end % no floating base
if isnumeric(options.floating) || islogical(options.floating)
  if (options.floating)
    options.floating = 'rpy';
  else
    options.floating = '';
  end
end
if (~isfield(options,'inertial')), options.inertial = true; end
if (~isfield(options,'visual')), options.visual = true; end
if (~isfield(options,'collision')), options.collision = true; end
if (~isfield(options,'nameprefix')), options.nameprefix = ''; end
if (~isfield(options,'namesuffix')), options.namesuffix = ''; end
if (~isfield(options,'compile')) options.compile = true; end
if (~isfield(options, 'weld_to_link')) options.weld_to_link = 1; end % world link 

sdf = xmlread(sdf_filename);
sdf = sdf.getElementsByTagName('sdf').item(0);

worlds = sdf.getElementsByTagName('world');
for i=0:(worlds.getLength-1)
  model = parseSDFWorld(model,worlds.item(i),xyz,rpy,options);
end

models = sdf.getElementsByTagName('model');
for i=0:(models.getLength-1)
  if (models.item(i).getParentNode()~=sdf), continue; end
  model = parseSDFModel(model,models.item(i),xyz,rpy,options);
end

includes = sdf.getElementsByTagName('include');
for i=0:(includes.getLength()-1)
  if (includes.item(i).getParentNode()~=sdf), continue; end
  model = parseInclude(model,1,includes.item(i),xyz,rpy,options);
end

model.dirty = true;
if options.compile
  model = compile(model); % ideally this would happen on entry into any function...
end

end

function model=parseSDFWorld(model,node,xyz,rpy,options)

worldname = char(node.getAttribute('name'));
worldname = regexprep(worldname, '\.', '_', 'preservecase');
options.nameprefix = [worldname,'_',options.nameprefix];

models = node.getElementsByTagName('model');
for i=0:(models.getLength-1)
  if (models.item(i).getParentNode()~=node), continue; end
  model = parseSDFModel(model,models.item(i),xyz,rpy,options);
end

includes = node.getElementsByTagName('include');
for i=0:(includes.getLength()-1)
  if (includes.item(i).getParentNode()~=node), continue; end
  model = parseInclude(model,1,includes.item(i),xyz,rpy,options);
end

end

function model=parseSDFModel(model,node,xyz,rpy,options)
% Constructs a model from an XML node

staticNode = node.getElementsByTagName('static').item(0);
if ~isempty(staticNode)
  options.static = parseParamString(model,1,char(getNodeValue(getFirstChild(staticNode))));
elseif ~isfield(options,'static')
  options.static = false;
end

if options.static
  robotnum = 1;
else
  %disp(['Parsing robot ', char(node.getAttribute('name')), ' from URDF file...']);
  robotname = char(node.getAttribute('name'));
  robotname = regexprep(robotname, '\.', '_', 'preservecase');
  robotname = [options.nameprefix,robotname,options.namesuffix];
  model.name = [model.name, {robotname}];
  model.urdf = vertcat(model.urdf, '');
  robotnum = length(model.name);
end

posenode = node.getElementsByTagName('pose').item(0);  % seems to be ok, even if pose tag doesn't exist
if ~isempty(posenode)
  pose = parseParamString(model,robotnum,char(getNodeValue(getFirstChild(posenode))));
  pose = pose(:);
  xyz = xyz + rpy2rotmat(rpy)*pose(1:3); rpy = rotmat2rpy(rpy2rotmat(rpy)*rpy2rotmat(pose(4:6)));
end

includes = node.getElementsByTagName('include');
for i=0:(includes.getLength()-1)
  if (includes.item(i).getParentNode()~=node), continue; end
  if ~options.static, options.nameprefix = [robotname,'_']; end
  model = parseInclude(model,robotnum,includes.item(i),xyz,rpy,options);
end

materials = node.getElementsByTagName('material');
for i=0:(materials.getLength()-1)
  [~,options] = model.parseMaterial(materials.item(i),options);
end

links = node.getElementsByTagName('link');
for i=0:(links.getLength()-1)
  model = parseLink(model,robotnum,links.item(i),xyz,rpy,options);
end

if ~options.static
  joints = node.getElementsByTagName('joint');
  for i=0:(joints.getLength()-1)
    model.warning_manager.warnOnce('Drake:RigidBodyManipulator:ParseSDF:JointsNotImplementedYet','i haven''t actually implemented joints yet ;-/');
    %  model = parseJoint(model,robotnum,joints.item(i),options);
  end
  model = removeFixedJoints(model);  % do this early and often, to help scale to more complex environments.

  ind = find([model.body.parent]<1);
  rootlink = ind([model.body(ind).robotnum]==robotnum);
  for i=1:length(rootlink)
    if ~isempty(options.floating)
      model = addFloatingBase(model,options.weld_to_link,rootlink(i),xyz,rpy,options.floating);
    else
      model = addJoint(model,'','fixed',options.weld_to_link,rootlink(i),xyz,rpy);
    end
  end
end

end

function model=parseInclude(model,robotnum,node,xyz,rpy,options)

staticNode = node.getElementsByTagName('static').item(0);
if ~isempty(staticNode)
  options.static = parseParamString(model,1,char(getNodeValue(getFirstChild(staticNode))));
elseif ~isfield(options,'static')
  options.static = false;
end

posenode = node.getElementsByTagName('pose').item(0);  % seems to be ok, even if pose tag doesn't exist
if ~isempty(posenode)
  pose = parseParamString(model,robotnum,char(getNodeValue(getFirstChild(posenode))));
  pose = pose(:);
  xyz = xyz + rpy2rotmat(rpy)*pose(1:3); rpy = rotmat2rpy(rpy2rotmat(rpy)*rpy2rotmat(pose(4:6)));
end

uriNode = node.getElementsByTagName('uri').item(0);
filename = char(getNodeValue(getFirstChild(uriNode)));

% parse strings with forward and backward slashes
filename = strrep(filename,'/',filesep);
filename = strrep(filename,'\',filesep);
            
if ~isempty(strfind(filename,['model:',filesep,filesep]))
  filename=strrep(filename,['model:',filesep,filesep],'');
  [gazebo_model,filename]=strtok(filename,filesep);
  filename=[gazeboModelPath(gazebo_model),filename];
  filename = fullfile(filename,'model.sdf');
else
  strrep(filename,'file://','');
  if ~isempty(strfind(filename,'http://'))
    error('urls not supported yet -- but might not be too hard');
  end
  [path,name,ext] = fileparts(filename);
  if (isempty(path) || path(1)~=filesep)  % the it's a relative path
    path = fullfile(options.urdfpath,path);
  end
  filename = fullfile(path,[name,ext]);
end
            
options.compile = false;
model = addRobotFromSDF(model,filename,xyz,rpy,options);

end

function model=parseLink(model,robotnum,node,xyz,rpy,options)

ignore = char(node.getAttribute('drakeIgnore'));
if strcmp(lower(ignore),'true')
  return;
end

staticNode = node.getElementsByTagName('static').item(0);
if ~isempty(staticNode)
  options.static = parseParamString(model,1,char(getNodeValue(getFirstChild(staticNode))));
elseif ~isfield(options,'static')
  options.static = false;
end

if options.static
  body = model.body(1);
else
  body = RigidBody();
  body.robotnum = robotnum;

  body.linkname=char(node.getAttribute('name'));
  body.linkname=regexprep(body.linkname, '[\[\]\\\/\.]+', '_', 'preservecase');
end

if (options.inertial && node.getElementsByTagName('inertial').getLength()>0)
  body = parseInertial(body,node.getElementsByTagName('inertial').item(0),model,xyz,rpy,options);
end

if (options.visual && node.getElementsByTagName('visual').getLength()>0)
  visualItem = 0;
  while(~isempty(node.getElementsByTagName('visual').item(visualItem)))
    body = parseVisual(body,node.getElementsByTagName('visual').item(visualItem),model,xyz,rpy,options);
    visualItem = visualItem+1;
  end
end

if (options.collision && node.getElementsByTagName('collision').getLength()>0)
  collisionItem = 0;
  while(~isempty(node.getElementsByTagName('collision').item(collisionItem)))
    body = parseCollision(body,node.getElementsByTagName('collision').item(collisionItem),model,xyz,rpy,options);
    collisionItem = collisionItem+1;
  end
end

if options.static
  model.body(1) = body;
else
  model.body=[model.body,body];
end

end

    function body=parseInertial(body,node,model,xyz,rpy,options)
      mass = 0;
      inertia = zeros(3);
      posenode = node.getElementsByTagName('pose').item(0);  % seems to be ok, even if pose tag doesn't exist
      if ~isempty(posenode)
        pose = parseParamString(model,body.robotnum,char(getNodeValue(getFirstChild(posenode))));
        pose = pose(:);
        xyz = xyz + rpy2rotmat(rpy)*pose(1:3); rpy = rotmat2rpy(rpy2rotmat(rpy)*rpy2rotmat(pose(4:6)));
      end
      massnode = node.getElementsByTagName('mass').item(0);
      if ~isempty(massnode)
        mass = parseParamString(model,body.robotnum,char(getNodeValue(getFirstChild(massnode))));
      end
      inode = node.getElementsByTagName('inertia').item(0);
      if ~isempty(inode)
        ii=inode.getElementsByTagName('ixx').item(0);
        if ~isempty(ii), ixx = parseParamString(model,body.robotnum,char(getNodeValue(getFirstChild(ii)))); else ixx=0; end
        ii=inode.getElementsByTagName('ixy').item(0);
        if ~isempty(ii), ixy = parseParamString(model,body.robotnum,char(getNodeValue(getFirstChild(ii)))); else ixy=0; end
        ii=inode.getElementsByTagName('ixz').item(0);
        if ~isempty(ii), ixz = parseParamString(model,body.robotnum,char(getNodeValue(getFirstChild(ii)))); else ixz=0; end
        ii=inode.getElementsByTagName('iyy').item(0);
        if ~isempty(ii), iyy = parseParamString(model,body.robotnum,char(getNodeValue(getFirstChild(ii)))); else iyy=0; end
        ii=inode.getElementsByTagName('iyz').item(0);
        if ~isempty(ii), iyz = parseParamString(model,body.robotnum,char(getNodeValue(getFirstChild(ii)))); else iyz=0; end
        ii=inode.getElementsByTagName('izz').item(0);
        if ~isempty(ii), izz = parseParamString(model,body.robotnum,char(getNodeValue(getFirstChild(ii)))); else izz=0; end
        inertia = [ixx, ixy, ixz; ixy, iyy, iyz; ixz, iyz, izz];
      end
      
      if any(rpy)
        % transform inertia back into body coordinates
        R = rpy2rotmat(rpy);
        inertia = R*inertia*R';
      end
      
      % add to existing mass/inertia (especially to support static objects)
      if ~isempty(body.com)
        xyz = (body.com*body.mass + xyz*mass)/(body.mass+mass);
        inertia = body.inertia + inertia; % should already be in the same frame
        mass = body.mass + mass;
      end
      
      body = setInertial(body,mass,xyz,inertia);
    end
    
    function body = parseVisual(body,node,model,xyz,rpy,options)
      c = .7*[1 1 1];
      
      posenode = node.getElementsByTagName('pose').item(0);  % seems to be ok, even if pose tag doesn't exist
      if ~isempty(posenode)
        pose = parseParamString(model,body.robotnum,char(getNodeValue(getFirstChild(posenode))));
        pose = pose(:);
        xyz = xyz + rpy2rotmat(rpy)*pose(1:3); rpy = rotmat2rpy(rpy2rotmat(rpy)*rpy2rotmat(pose(4:6)));
      end
        
      matnode = node.getElementsByTagName('material').item(0);
      if ~isempty(matnode)
        model.warning_manager.warnOnce('Drake:RigidBodyManipulator:addRobotfromSDF:NoMaterials','materials not implemented yet');
      end
      
      geomnode = node.getElementsByTagName('geometry').item(0);
      if ~isempty(geomnode)
        if (options.visual || options.visual_geometry)
         geometry = RigidBodyGeometry.parseSDFNode(geomnode,xyz,rpy,model,body.robotnum,options);
         if ~isempty(geometry)
           geometry.c = c;
           body.visual_geometry = {body.visual_geometry{:},geometry};
         end
        end
      end        
    end
    
    function body = parseCollision(body,node,model,xyz,rpy,options)
      posenode = node.getElementsByTagName('pose').item(0);  % seems to be ok, even if pose tag doesn't exist
      if ~isempty(posenode)
        pose = parseParamString(model,body.robotnum,char(getNodeValue(getFirstChild(posenode))));
        pose = pose(:);
        xyz = xyz + rpy2rotmat(rpy)*pose(1:3); rpy = rotmat2rpy(rpy2rotmat(rpy)*rpy2rotmat(pose(4:6)));
      end
            
      geomnode = node.getElementsByTagName('geometry').item(0);
      if ~isempty(geomnode)
        geometry = RigidBodyGeometry.parseSDFNode(geomnode,xyz,rpy,model,body.robotnum,options);
        body = addCollisionGeometry(body,geometry);
      end
    end 
