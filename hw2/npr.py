"""HW2.7 plus adapted toon, TAM hatching and depth/normal feature lines."""
from pathlib import Path
import time
import json
import numpy as np
from PIL import Image
import slangpy as spy
import buffer
import device
import image
import window
from . import hw2_scene
from .hw2 import interpolate_transformation, create_Kd_texture

STYLES = {'phong': 0, 'toon': 1, 'lines': 2, 'hatching': 3, 'combined': 4}


def animated_matrix(static, keyframes, t):
    if not keyframes:
        return static
    return hw2_scene.compose_transformations(interpolate_transformation(keyframes, t))


class NPRRenderer:
    def __init__(self, args):
        self.args = args
        self.device = spy.create_device()
        self.scene = hw2_scene.parse_scene(args.scene)
        camera = self.scene.camera
        source = json.loads(Path(args.scene).read_text())
        self.light_position = source.get('light', {}).get('position')
        self.ssaa = args.ssaa
        self.width, self.height = camera.resolution
        w, h = self.width*self.ssaa, self.height*self.ssaa
        self.render_width, self.render_height = w, h
        self.program = self.device.load_program('hw2/npr_lighting.slang', ['vertex_main', 'fragment_main'])
        self.lines = device.load_compute_shader(self.device, 'hw2/npr_lines.slang')
        self.color = self.device.create_texture(width=w, height=h, format=spy.Format.rgba32_float,
            usage=spy.TextureUsage.render_target | spy.TextureUsage.shader_resource | spy.TextureUsage.copy_source)
        self.geometry = self.device.create_texture(width=w, height=h, format=spy.Format.rgba32_float,
            usage=spy.TextureUsage.render_target | spy.TextureUsage.shader_resource | spy.TextureUsage.copy_source)
        self.depth = self.device.create_texture(width=w, height=h, format=spy.Format.d32_float,
            usage=spy.TextureUsage.depth_stencil)
        self.output = buffer.create_texture_2d(self.device, self.width, self.height)
        self.pipeline = self.device.create_render_pipeline(program=self.program, input_layout=None,
            primitive_topology=spy.PrimitiveTopology.triangle_list,
            targets=[spy.ColorTargetDesc({'format': spy.Format.rgba32_float}) for _ in range(2)],
            depth_stencil=spy.DepthStencilDesc({'format': spy.Format.d32_float,
                'depth_test_enable': True, 'depth_write_enable': True, 'depth_func': spy.ComparisonFunc.less}),
            rasterizer=spy.RasterizerDesc({'cull_mode': spy.CullMode.none}))
        # Both MRTs are written only by the closest fragment, keeping depth/normals coherent.
        self.color_view = self.color.create_view()
        self.geometry_view = self.geometry.create_view()
        self.depth_view = self.depth.create_view()
        self.render_pass_desc = spy.RenderPassDesc({
            'color_attachments': [
                spy.RenderPassColorAttachment({'view': self.color_view,
                    'load_op': spy.LoadOp.clear, 'store_op': spy.StoreOp.store,
                    'clear_value': spy.float4(*self.scene.background, 1.0)}),
                spy.RenderPassColorAttachment({'view': self.geometry_view,
                    'load_op': spy.LoadOp.clear, 'store_op': spy.StoreOp.store,
                    'clear_value': spy.float4(0.5,0.5,0.0,0.0)})],
            'depth_stencil_attachment': spy.RenderPassDepthStencilAttachment({
                'view': self.depth_view, 'depth_load_op': spy.LoadOp.clear,
                'depth_store_op': spy.StoreOp.dont_care, 'depth_clear_value': 1.0})})
        self.meshes = []
        for mesh in self.scene.meshes:
            gpu = {}
            for name, dtype in [('vertices', 'float3'), ('vertex_normals', 'float3'), ('vertex_uvs', 'float2')]:
                gpu[name] = buffer.structured_typed_buffer_from_numpy(self.device, getattr(mesh, name), dtype)
            indices = np.ascontiguousarray(mesh.faces.reshape(-1), dtype=np.uint32)
            gpu['indices'] = self.device.create_buffer(size=indices.nbytes, usage=spy.BufferUsage.index_buffer, data=indices)
            gpu['state'] = spy.RenderState({'viewports': [spy.Viewport.from_size(w,h)],
                'scissor_rects': [spy.ScissorRect.from_size(w,h)],
                'index_buffer': spy.BufferOffsetPair(gpu['indices']), 'index_format': spy.IndexFormat.uint32})
            gpu['Kd_texture'] = create_Kd_texture(self.device, mesh.material, str(Path(args.scene).parent))
            self.meshes.append(gpu)
        self.Kd_sampler = self.device.create_sampler()
        self.hatches = []
        for index in range(6):
            rgba = np.array(Image.open(Path(__file__).parent/'npr_assets'/f'hatch_{index}.jpg').convert('RGBA'), dtype=np.uint8)
            self.hatches.append(self.device.create_texture(width=rgba.shape[1], height=rgba.shape[0],
                format=spy.Format.rgba8_unorm, usage=spy.TextureUsage.shader_resource, data=rgba.ravel()))
        a = self.width/self.height
        self.projection = np.array([[1/(camera.s*a),0,0,0], [0,1/camera.s,0,0],
            [0,0,-1,-camera.z_near], [0,0,-1,0]], dtype=np.float32)

    def render(self, encoder, t, style='combined'):
        scene, camera, args = self.scene, self.scene.camera, self.args
        t %= scene.duration
        cam_to_world = animated_matrix(camera.cam_to_world, camera.transform_keyframes, t)
        view = np.linalg.inv(cam_to_world).astype(np.float32)
        render_pass = encoder.begin_render_pass(self.render_pass_desc)
        for mesh, gpu in zip(scene.meshes, self.meshes):
            model = animated_matrix(mesh.model_matrix, mesh.transform_keyframes, t)
            normal = np.linalg.inv(model[:3,:3]).T.astype(np.float32)
            root = render_pass.bind_pipeline(self.pipeline)
            cursor = spy.ShaderCursor(root)
            fields = dict(MVP=spy.float4x4(self.projection@view@model),
                model_matrix=spy.float4x4(model), normal_matrix=spy.float3x3(normal),
                vertices=gpu['vertices'], vertex_normals=gpu['vertex_normals'], vertex_uvs=gpu['vertex_uvs'],
                Kd_texture=gpu['Kd_texture'], Kd_sampler=self.Kd_sampler,
                light_dir=spy.float3(scene.light_dir),
                light_position=spy.float3(self.light_position or [0,0,0]),
                point_light=self.light_position is not None,
                object_color=spy.float3(mesh.material['Kd']), use_texture='texture' in mesh.material, light_color=spy.float3(scene.light_color),
                camera_position=spy.float3(cam_to_world[:3,3]), Ks=spy.float3(mesh.material['Ks']),
                exponent=float(mesh.material['exponent']), style=STYLES[style], color_steps=float(args.color_steps),
                hatch_strength=float(args.hatch_strength), shadow_lift=float(args.shadow_lift), hatch_scale=float(args.hatch_scale),
                resolution_scale=float(self.ssaa), render_height=self.render_height)
            fields.update({f'hatch{i}': tex for i, tex in enumerate(self.hatches)})
            for name, value in fields.items():
                cursor.find_field(name).write(value)
            render_pass.set_render_state(gpu['state'])
            render_pass.draw_indexed(spy.DrawArguments({'vertex_count': int(mesh.faces.size),
                                                      'instance_count': 1, 'start_index_location': 0}))
        render_pass.end()
        encoder.global_barrier()
        self.lines.kernel.dispatch(thread_count=[self.width,self.height,1], command_encoder=encoder,
            vars=dict(scene_color=self.color, normal_depth=self.geometry, output_image=self.output,
            width=self.render_width, height=self.render_height, style=STYLES[style], ssaa=self.ssaa,
            line_width=float(args.line_width), normal_threshold=float(args.normal_threshold),
            depth_threshold=float(args.depth_threshold), line_opacity=float(args.line_opacity),
            ink_color=spy.float3(args.ink_color)))

    def pixels(self, t, style):
        encoder = self.device.create_command_encoder()
        self.render(encoder, t, style)
        submit = self.device.submit_command_buffer(encoder.finish())
        self.device.wait_for_submit(submit)
        result = self.output.to_numpy()
        if not np.isfinite(result).all():
            raise RuntimeError('Non-finite values in rendered image')
        return result

    def save(self, filename, t, style):
        start = time.perf_counter()
        result = self.pixels(t, style)
        image.save_png(filename, result)
        print(f'{style}: {filename} ({time.perf_counter()-start:.3f}s, {self.width}x{self.height}, SSAA {self.ssaa})')
        return result


def run(args):
    if args.hatch_scale <= 0 or args.line_width <= 0 or args.normal_threshold <= 0 or args.depth_threshold <= 0:
        raise ValueError('Scale, line width and edge thresholds must be positive')
    if not all(0 <= x <= 1 for x in [args.hatch_strength,args.shadow_lift,args.line_opacity]):
        raise ValueError('Hatch strength, shadow lift and line opacity must be in [0,1]')
    if args.frames < 2 or args.fps < 1:
        raise ValueError('Turntable requires at least 2 frames and a positive FPS')
    renderer = NPRRenderer(args)
    if args.compare:
        directory = Path(args.compare)
        for style in STYLES:
            renderer.save(directory/f'{Path(args.scene).stem}_{style}.png', args.time, style)
    elif args.turntable:
        frames = []
        for i in range(args.frames):
            result = renderer.pixels(i*renderer.scene.duration/args.frames, args.style)
            rgb = np.round(image.linear_to_srgb(result[...,:3])*255).astype(np.uint8)
            frame = Image.fromarray(rgb).resize((640,480), Image.Resampling.LANCZOS)
            frames.append(frame)
        destination = Path(args.turntable)
        destination.parent.mkdir(parents=True, exist_ok=True)
        frames[0].save(destination, save_all=True, append_images=frames[1:], duration=round(1000/args.fps), loop=0)
        print(f'Saved {len(frames)} rendered frames to {destination}')
    elif args.output:
        renderer.save(args.output, args.time, args.style)
    else:
        app = window.App(renderer.device, renderer.output)
        app.run({}, lambda enc, state, img: renderer.render(enc, state['time'], args.style),
                lambda t, state: {'time': t+args.time})


def add_arguments(parser):
    parser.add_argument('scene', nargs='?', default='scenes/npr/teapot.json')
    parser.add_argument('-time', '--time', type=float, default=0.0)
    parser.add_argument('--style', choices=list(STYLES), default='combined')
    parser.add_argument('--compare', metavar='DIRECTORY', help='Save all five styles without opening a window')
    parser.add_argument('--turntable', metavar='GIF', help='Render a complete animation loop')
    parser.add_argument('--frames', type=int, default=48)
    parser.add_argument('--fps', type=int, default=12)
    parser.add_argument('--ssaa', type=int, choices=[1,2,3], default=2)
    parser.add_argument('--color-steps', type=int, choices=range(2,9), default=3)
    parser.add_argument('--hatch-strength', type=float, default=0.4)
    parser.add_argument('--shadow-lift', type=float, default=0.24, help='Combined style only: preserve ink contrast in shadow bands')
    parser.add_argument('--hatch-scale', type=float, default=1.0)
    parser.add_argument('--line-width', type=float, default=1.0)
    parser.add_argument('--normal-threshold', type=float, default=0.085)
    parser.add_argument('--depth-threshold', type=float, default=0.04)
    parser.add_argument('--line-opacity', type=float, default=1.0)
    parser.add_argument('--ink-color', type=float, nargs=3, default=[0.012,0.009,0.007])
    parser.set_defaults(func=run)
