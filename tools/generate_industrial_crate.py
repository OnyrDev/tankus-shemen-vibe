#!/usr/bin/env python3
"""
Procedural 3D Model Generator for the Heavy Industrial Crate (TANKUS).
Generates a watertight, beveled, vertex-colored & PBR-textured Binary glTF 2.0 (.glb) model
matching the reference industrial crate design.
"""

import json
import math
import os
import random
import struct
import zlib
from typing import List, Tuple, Optional

Vec2 = Tuple[float, float]
Vec3 = Tuple[float, float, float]
Color4 = Tuple[float, float, float, float]
HalfPlane = Tuple[float, float, float, float]  # (nu, nv, dist, shrink_scale)


def v3_add(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def v3_sub(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def v3_scale(a: Vec3, s: float) -> Vec3:
    return (a[0] * s, a[1] * s, a[2] * s)


def v3_dot(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def v3_cross(a: Vec3, b: Vec3) -> Vec3:
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def v3_len(a: Vec3) -> float:
    return math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])


def v3_norm(a: Vec3) -> Vec3:
    length = v3_len(a)
    if length < 1e-12:
        return (0.0, 1.0, 0.0)
    return (a[0] / length, a[1] / length, a[2] / length)


def clamp01(x: float) -> float:
    return max(0.0, min(1.0, x))


def tint_color(base: Color4, factor: float, pos: Vec3) -> Color4:
    n = math.sin(pos[0] * 19.3 + pos[1] * 27.1 + pos[2] * 23.7) * 0.012
    f = factor + n
    return (
        clamp01(base[0] * f),
        clamp01(base[1] * f),
        clamp01(base[2] * f),
        base[3],
    )


class MeshBuilder:
    def __init__(self, scale: float = 0.70) -> None:
        self.scale = scale
        self.positions: List[Vec3] = []
        self.normals: List[Vec3] = []
        self.uvs: List[Vec2] = []
        self.colors: List[Color4] = []
        self.indices: List[int] = []
        self._transform_mode: int = 0
        self._flip_y: bool = False

    def set_symmetry(self, rot_y_90: int = 0, flip_y: bool = False) -> None:
        self._transform_mode = rot_y_90 % 4
        self._flip_y = flip_y

    def _apply_sym(self, p: Vec3) -> Vec3:
        x, y, z = p
        if self._flip_y:
            y = -y
        if self._transform_mode == 1:
            x, z = z, -x
        elif self._transform_mode == 2:
            x, z = -x, -z
        elif self._transform_mode == 3:
            x, z = -z, x
        return (x * self.scale, y * self.scale, z * self.scale)

    def _apply_sym_dir(self, d: Vec3) -> Vec3:
        x, y, z = d
        if self._flip_y:
            y = -y
        if self._transform_mode == 1:
            x, z = z, -x
        elif self._transform_mode == 2:
            x, z = -x, -z
        elif self._transform_mode == 3:
            x, z = -z, x
        return v3_norm((x, y, z))

    def _box_uv(self, p: Vec3, n: Vec3) -> Vec2:
        ax, ay, az = abs(n[0]), abs(n[1]), abs(n[2])
        if ay >= ax and ay >= az:
            return (p[0] * 0.75 + 0.5, p[2] * 0.75 + 0.5)
        elif ax >= ay and ax >= az:
            return (p[2] * 0.75 + 0.5, p[1] * 0.75 + 0.5)
        else:
            return (p[0] * 0.75 + 0.5, p[1] * 0.75 + 0.5)

    def add_tri(
        self,
        a: Vec3,
        b: Vec3,
        c: Vec3,
        ca: Color4,
        cb: Color4,
        cc: Color4,
        outward_hint: Optional[Vec3] = None,
    ) -> None:
        pa = self._apply_sym(a)
        pb = self._apply_sym(b)
        pc = self._apply_sym(c)

        ab = v3_sub(pb, pa)
        ac = v3_sub(pc, pa)
        cross = v3_cross(ab, ac)
        if v3_len(cross) < 1e-11:
            return
        n = v3_norm(cross)

        if outward_hint is not None:
            hint = self._apply_sym_dir(outward_hint)
            if v3_dot(n, hint) < 0.0:
                pb, pc = pc, pb
                cb, cc = cc, cb
                n = (-n[0], -n[1], -n[2])
        elif self._flip_y:
            pb, pc = pc, pb
            cb, cc = cc, cb
            n = (-n[0], -n[1], -n[2])

        base_idx = len(self.positions)
        for pos, col in ((pa, ca), (pb, cb), (pc, cc)):
            self.positions.append(pos)
            self.normals.append(n)
            self.uvs.append(self._box_uv(pos, n))
            self.colors.append(tint_color(col, 1.0, pos))
        self.indices.extend([base_idx, base_idx + 1, base_idx + 2])

    def add_quad(
        self,
        a: Vec3,
        b: Vec3,
        c: Vec3,
        d: Vec3,
        ca: Color4,
        cb: Color4,
        cc: Color4,
        cd: Color4,
        outward_hint: Optional[Vec3] = None,
    ) -> None:
        self.add_tri(a, b, c, ca, cb, cc, outward_hint)
        self.add_tri(a, c, d, ca, cc, cd, outward_hint)

    def loft_halfplanes(
        self,
        origin: Vec3,
        eu: Vec3,
        ev: Vec3,
        ew: Vec3,
        planes: List[HalfPlane],
        layers: List[Tuple[float, float, Color4]],
        cap_top: bool = True,
        cap_bottom: bool = False,
    ) -> None:
        num_edges = len(planes)
        rings: List[List[Vec3]] = []
        ring_colors: List[Color4] = []

        for w_val, delta, col in layers:
            pts: List[Vec3] = []
            for i in range(num_edges):
                nu1, nv1, d1, s1 = planes[i - 1]
                nu2, nv2, d2, s2 = planes[i]
                sd1 = d1 - delta * s1
                sd2 = d2 - delta * s2
                det = nu1 * nv2 - nv1 * nu2
                if abs(det) < 1e-9:
                    u, v = 0.0, 0.0
                else:
                    u = (sd1 * nv2 - nv1 * sd2) / det
                    v = (nu1 * sd2 - sd1 * nu2) / det
                p = v3_add(
                    origin,
                    v3_add(v3_scale(eu, u), v3_add(v3_scale(ev, v), v3_scale(ew, w_val))),
                )
                pts.append(p)
            rings.append(pts)
            ring_colors.append(col)

        for k in range(len(layers) - 1):
            r0 = rings[k]
            r1 = rings[k + 1]
            c0 = ring_colors[k]
            c1 = ring_colors[k + 1]
            dw = layers[k + 1][0] - layers[k][0]
            dd = layers[k + 1][1] - layers[k][1]
            for i in range(num_edges):
                nu, nv, _, _ = planes[i]
                edge_out_2d = v3_add(v3_scale(eu, nu), v3_scale(ev, nv))
                hint = v3_add(v3_scale(edge_out_2d, max(0.08, abs(dw))), v3_scale(ew, dd))
                if v3_len(hint) < 1e-6:
                    hint = edge_out_2d
                j = (i + 1) % num_edges
                self.add_quad(r0[i], r0[j], r1[j], r1[i], c0, c0, c1, c1, hint)

        if cap_top and len(rings) > 0:
            top_ring = rings[-1]
            top_col = ring_colors[-1]
            for i in range(1, num_edges - 1):
                self.add_tri(
                    top_ring[0],
                    top_ring[i],
                    top_ring[i + 1],
                    top_col,
                    top_col,
                    top_col,
                    ew,
                )

        if cap_bottom and len(rings) > 0:
            bot_ring = rings[0]
            bot_col = ring_colors[0]
            neg_ew = v3_scale(ew, -1.0)
            for i in range(1, num_edges - 1):
                self.add_tri(
                    bot_ring[0],
                    bot_ring[i + 1],
                    bot_ring[i],
                    bot_col,
                    bot_col,
                    bot_col,
                    neg_ew,
                )

    def build_holed_plate(
        self,
        origin: Vec3,
        eu: Vec3,
        ev: Vec3,
        ew: Vec3,
        outer_u: Tuple[float, float],
        outer_v: Tuple[float, float],
        hole_u: Tuple[float, float],
        hole_v: Tuple[float, float],
        outer_layers: List[Tuple[float, float, Color4]],
        hole_layers: List[Tuple[float, float, Color4]],
        floor_color: Color4,
        outer_corner_chamfer: float = 0.0,
    ) -> None:
        if outer_corner_chamfer > 1e-5:
            planes = rect_chamfered_planes(
                outer_u[0], outer_u[1], outer_v[0], outer_v[1], outer_corner_chamfer
            )
            self.loft_halfplanes(origin, eu, ev, ew, planes, outer_layers, cap_top=False)
        else:
            planes = rect_planes(outer_u[0], outer_u[1], outer_v[0], outer_v[1])
            self.loft_halfplanes(origin, eu, ev, ew, planes, outer_layers, cap_top=False)

        w_top, d_top, col_top = outer_layers[-1]
        u0 = outer_u[0] + d_top
        u1 = outer_u[1] - d_top
        v0 = outer_v[0] + d_top
        v1 = outer_v[1] - d_top

        hw_top, hd_top, hcol_top = hole_layers[0]
        hu0 = hole_u[0] - hd_top
        hu1 = hole_u[1] + hd_top
        hv0 = hole_v[0] - hd_top
        hv1 = hole_v[1] + hd_top

        def pt(u: float, v: float, w: float) -> Vec3:
            return v3_add(
                origin, v3_add(v3_scale(eu, u), v3_add(v3_scale(ev, v), v3_scale(ew, w)))
            )

        c = (
            max(0.0, outer_corner_chamfer + (2.0 - math.sqrt(2.0)) * d_top)
            if outer_corner_chamfer > 1e-5
            else 0.0
        )

        o_b0 = pt(u0 + c, v0, w_top)
        o_b1 = pt(u1 - c, v0, w_top)
        o_r0 = pt(u1, v0 + c, w_top)
        o_r1 = pt(u1, v1 - c, w_top)
        o_t1 = pt(u1 - c, v1, w_top)
        o_t0 = pt(u0 + c, v1, w_top)
        o_l1 = pt(u0, v1 - c, w_top)
        o_l0 = pt(u0, v0 + c, w_top)

        i_bl = pt(hu0, hv0, hw_top)
        i_br = pt(hu1, hv0, hw_top)
        i_tr = pt(hu1, hv1, hw_top)
        i_tl = pt(hu0, hv1, hw_top)

        self.add_quad(o_b0, o_b1, i_br, i_bl, col_top, col_top, hcol_top, hcol_top, ew)
        self.add_quad(o_r0, o_r1, i_tr, i_br, col_top, col_top, hcol_top, hcol_top, ew)
        self.add_quad(o_t1, o_t0, i_tl, i_tr, col_top, col_top, hcol_top, hcol_top, ew)
        self.add_quad(o_l1, o_l0, i_bl, i_tl, col_top, col_top, hcol_top, hcol_top, ew)

        if c > 1e-5:
            self.add_tri(o_b1, o_r0, i_br, col_top, col_top, hcol_top, ew)
            self.add_tri(o_r1, o_t1, i_tr, col_top, col_top, hcol_top, ew)
            self.add_tri(o_t0, o_l1, i_tl, col_top, col_top, hcol_top, ew)
            self.add_tri(o_l0, o_b0, i_bl, col_top, col_top, hcol_top, ew)

        hole_rings: List[List[Vec3]] = []
        for hw, hd, _ in hole_layers:
            cur_u0 = hole_u[0] - hd
            cur_u1 = hole_u[1] + hd
            cur_v0 = hole_v[0] - hd
            cur_v1 = hole_v[1] + hd
            hole_rings.append(
                [
                    pt(cur_u0, cur_v0, hw),
                    pt(cur_u1, cur_v0, hw),
                    pt(cur_u1, cur_v1, hw),
                    pt(cur_u0, cur_v1, hw),
                ]
            )

        inward_dirs = [
            v3_scale(ev, 1.0),
            v3_scale(eu, -1.0),
            v3_scale(ev, -1.0),
            v3_scale(eu, 1.0),
        ]

        for k in range(len(hole_layers) - 1):
            r0 = hole_rings[k]
            r1 = hole_rings[k + 1]
            c0 = hole_layers[k][2]
            c1 = hole_layers[k + 1][2]
            for i in range(4):
                j = (i + 1) % 4
                hint = v3_add(inward_dirs[i], v3_scale(ew, 0.35))
                self.add_quad(r0[i], r0[j], r1[j], r1[i], c0, c0, c1, c1, hint)

        bot = hole_rings[-1]
        self.add_quad(
            bot[0], bot[1], bot[2], bot[3], floor_color, floor_color, floor_color, floor_color, ew
        )


def rect_planes(u0: float, u1: float, v0: float, v1: float) -> List[HalfPlane]:
    return [
        (0.0, -1.0, -v0, 1.0),
        (1.0, 0.0, u1, 1.0),
        (0.0, 1.0, v1, 1.0),
        (-1.0, 0.0, -u0, 1.0),
    ]


def rect_chamfered_planes(
    u0: float, u1: float, v0: float, v1: float, c: float
) -> List[HalfPlane]:
    inv_s2 = 1.0 / math.sqrt(2.0)
    return [
        (0.0, -1.0, -v0, 1.0),
        (inv_s2, -inv_s2, (u1 - v0 - c) * inv_s2, 1.0),
        (1.0, 0.0, u1, 1.0),
        (inv_s2, inv_s2, (u1 + v1 - c) * inv_s2, 1.0),
        (0.0, 1.0, v1, 1.0),
        (-inv_s2, inv_s2, (-u0 + v1 - c) * inv_s2, 1.0),
        (-1.0, 0.0, -u0, 1.0),
        (-inv_s2, -inv_s2, (-u0 - v0 - c) * inv_s2, 1.0),
    ]


# ==============================================================================
# COLOR PALETTE — Rich Dark Gunmetal & Slate Steel (matching reference photo)
# Note: Vertex colors in glTF 2.0 are linear RGB!
# Srgb ~0.35 corresponds to Linear ~0.10, Srgb ~0.42 -> Linear ~0.145
# ==============================================================================
def srgb_to_lin(c: float) -> float:
    return pow(max(0.0, c), 2.2)


def srgb(r: float, g: float, b: float) -> Color4:
    return (srgb_to_lin(r), srgb_to_lin(g), srgb_to_lin(b), 1.0)


COL_CAVITY: Color4 = srgb(0.065, 0.072, 0.082)      # Deep dark pockets & slots
COL_SEAM_DARK: Color4 = srgb(0.115, 0.125, 0.142)   # Panel seams & groove bases
COL_FRAME_BASE: Color4 = srgb(0.215, 0.232, 0.255)  # Lower bevel transition
COL_FRAME_MAIN: Color4 = srgb(0.265, 0.286, 0.312)  # Main gunmetal frame & columns
COL_FRAME_EDGE: Color4 = srgb(0.375, 0.402, 0.435)  # Worn bevel edge highlight

COL_CLAMP_MAIN: Color4 = srgb(0.285, 0.308, 0.336)  # Heavy corner clamp body
COL_CLAMP_EDGE: Color4 = srgb(0.405, 0.435, 0.470)  # Clamp bevel edge highlight

COL_PANEL_DARK: Color4 = srgb(0.195, 0.212, 0.232)  # Recessed side panel / plank groove
COL_PANEL_MAIN: Color4 = srgb(0.222, 0.240, 0.264)  # Side panels & horizontal planks
COL_PANEL_EDGE: Color4 = srgb(0.325, 0.352, 0.382)  # Plank / panel bevel edge


def build_crate_mesh() -> MeshBuilder:
    mb = MeshBuilder(scale=0.70)  # 1.40m x 1.40m x 1.40m crate
    inv_s2 = 1.0 / math.sqrt(2.0)

    # --------------------------------------------------------------------------
    # 0. INNER DARK CAVITY CORE (sits at 0.78, behind all panels & handle slots)
    # --------------------------------------------------------------------------
    mb.set_symmetry(0, False)
    core_planes = rect_chamfered_planes(-0.78, 0.78, -0.78, 0.78, 0.06)
    mb.loft_halfplanes(
        origin=(0.0, 0.0, 0.0),
        eu=(1.0, 0.0, 0.0),
        ev=(0.0, 0.0, -1.0),
        ew=(0.0, 1.0, 0.0),
        planes=core_planes,
        layers=[(-0.78, 0.0, COL_CAVITY), (0.78, 0.0, COL_CAVITY)],
        cap_top=True,
        cap_bottom=True,
    )

    # --------------------------------------------------------------------------
    # 1. FOUR CORNER ASSEMBLIES (Columns + Top/Bottom Caps + Wrap-Around Clamps)
    # --------------------------------------------------------------------------
    def corner_post_planes(x_in: float, x_out: float, diag_sum: float) -> List[HalfPlane]:
        c_in = 0.012
        c_edge = 0.014
        c22, s22 = math.cos(math.pi / 8.0), math.sin(math.pi / 8.0)
        v_cham = diag_sum - x_out
        d22 = c22 * x_out + s22 * v_cham - 0.0055
        return [
            (0.0, -1.0, -x_in, 1.0),
            (inv_s2, -inv_s2, (x_out - x_in - c_edge) * inv_s2, 1.0),
            (1.0, 0.0, x_out, 1.0),
            (c22, s22, d22, 1.0),
            (inv_s2, inv_s2, diag_sum * inv_s2, 1.0),
            (s22, c22, d22, 1.0),
            (0.0, 1.0, x_out, 1.0),
            (-inv_s2, inv_s2, (x_out - x_in - c_edge) * inv_s2, 1.0),
            (-1.0, 0.0, -x_in, 1.0),
            (-inv_s2, -inv_s2, -(2.0 * x_in + c_in) * inv_s2, 1.0),
        ]

    col_planes = corner_post_planes(0.805, 0.995, 1.882)
    cap_planes = corner_post_planes(0.800, 1.004, 1.892)

    for rot in range(4):
        mb.set_symmetry(rot, False)

        # 1A. Vertical Corner Column segments
        col_segments = [
            (-0.802, -0.592),
            (-0.312, 0.312),
            (0.592, 0.802),
        ]
        for y0, y1 in col_segments:
            b = 0.012
            mb.loft_halfplanes(
                origin=(0.0, 0.0, 0.0),
                eu=(0.0, 0.0, 1.0),
                ev=(1.0, 0.0, 0.0),
                ew=(0.0, 1.0, 0.0),
                planes=col_planes,
                layers=[
                    (y0, b, COL_SEAM_DARK),
                    (y0 + b * 0.75, b * 0.2, COL_FRAME_EDGE),
                    (y0 + b, 0.0, COL_FRAME_MAIN),
                    (y1 - b, 0.0, COL_FRAME_MAIN),
                    (y1 - b * 0.75, b * 0.2, COL_FRAME_EDGE),
                    (y1, b, COL_SEAM_DARK),
                ],
                cap_top=True,
                cap_bottom=True,
            )

        # Inner dark spine behind column seams
        spine_planes = corner_post_planes(0.810, 0.980, 1.858)
        mb.loft_halfplanes(
            origin=(0.0, 0.0, 0.0),
            eu=(0.0, 0.0, 1.0),
            ev=(1.0, 0.0, 0.0),
            ew=(0.0, 1.0, 0.0),
            planes=spine_planes,
            layers=[(-0.96, 0.0, COL_SEAM_DARK), (0.96, 0.0, COL_SEAM_DARK)],
            cap_top=False,
            cap_bottom=False,
        )

        # 1B. Top and Bottom Corner Caps
        for flip_y in (False, True):
            mb.set_symmetry(rot, flip_y)
            mb.loft_halfplanes(
                origin=(0.0, 0.0, 0.0),
                eu=(0.0, 0.0, 1.0),
                ev=(1.0, 0.0, 0.0),
                ew=(0.0, 1.0, 0.0),
                planes=cap_planes,
                layers=[
                    (0.805, 0.015, COL_SEAM_DARK),
                    (0.818, 0.003, COL_FRAME_EDGE),
                    (0.824, 0.0, COL_FRAME_MAIN),
                    (0.960, 0.0, COL_FRAME_MAIN),
                    (0.972, 0.008, COL_FRAME_EDGE),
                    (0.996, 0.036, COL_FRAME_EDGE),
                    (1.003, 0.048, COL_FRAME_MAIN),
                ],
                cap_top=True,
                cap_bottom=True,
            )

        # 1C. Upper & Lower Wrap-Around Corner Clamps (with continuous collar backing)
        for y_center in (-0.452, 0.452):
            mb.set_symmetry(rot, False)
            h_half = 0.136

            # Continuous wrap-around collar base under the 3 faces of the clamp
            collar_planes = corner_post_planes(0.792, 1.030, 1.940)
            mb.loft_halfplanes(
                origin=(0.0, y_center, 0.0),
                eu=(0.0, 0.0, 1.0),
                ev=(1.0, 0.0, 0.0),
                ew=(0.0, 1.0, 0.0),
                planes=collar_planes,
                layers=[
                    (-h_half + 0.004, 0.016, COL_SEAM_DARK),
                    (-h_half + 0.016, 0.003, COL_CLAMP_EDGE),
                    (-h_half + 0.020, 0.0, COL_CLAMP_MAIN),
                    (h_half - 0.020, 0.0, COL_CLAMP_MAIN),
                    (h_half - 0.016, 0.003, COL_CLAMP_EDGE),
                    (h_half - 0.004, 0.016, COL_SEAM_DARK),
                ],
                cap_top=True,
                cap_bottom=True,
            )

            wing_outer_layers = [
                (1.015, 0.010, COL_SEAM_DARK),
                (1.024, 0.0, COL_CLAMP_MAIN),
                (1.042, 0.0, COL_CLAMP_MAIN),
                (1.055, 0.012, COL_CLAMP_EDGE),
                (1.060, 0.018, COL_CLAMP_MAIN),
            ]
            wing_hole_layers = [
                (1.060, 0.0, COL_CLAMP_EDGE),
                (1.044, -0.015, COL_FRAME_BASE),
                (0.985, -0.017, COL_CAVITY),
            ]

            # Left Wing (+Z face)
            mb.build_holed_plate(
                origin=(0.0, y_center, 0.0),
                eu=(1.0, 0.0, 0.0),
                ev=(0.0, 1.0, 0.0),
                ew=(0.0, 0.0, 1.0),
                outer_u=(0.788, 0.932),
                outer_v=(-h_half, h_half),
                hole_u=(0.835, 0.890),
                hole_v=(-0.042, 0.042),
                outer_layers=wing_outer_layers,
                hole_layers=wing_hole_layers,
                floor_color=COL_CAVITY,
                outer_corner_chamfer=0.010,
            )

            # Right Wing (+X face)
            mb.build_holed_plate(
                origin=(0.0, y_center, 0.0),
                eu=(0.0, 0.0, -1.0),
                ev=(0.0, 1.0, 0.0),
                ew=(1.0, 0.0, 0.0),
                outer_u=(-0.932, -0.788),
                outer_v=(-h_half, h_half),
                hole_u=(-0.890, -0.835),
                hole_v=(-0.042, 0.042),
                outer_layers=wing_outer_layers,
                hole_layers=wing_hole_layers,
                floor_color=COL_CAVITY,
                outer_corner_chamfer=0.010,
            )

            # Center 45-degree Diagonal Face of Clamp (with vertical slot)
            diag_outer_layers = [
                (1.352, 0.008, COL_SEAM_DARK),
                (1.364, 0.0, COL_CLAMP_MAIN),
                (1.392, 0.0, COL_CLAMP_MAIN),
                (1.405, 0.011, COL_CLAMP_EDGE),
                (1.410, 0.016, COL_CLAMP_MAIN),
            ]
            diag_hole_layers = [
                (1.410, 0.0, COL_CLAMP_EDGE),
                (1.395, -0.011, COL_FRAME_BASE),
                (1.340, -0.013, COL_CAVITY),
            ]
            mb.build_holed_plate(
                origin=(0.0, y_center, 0.0),
                eu=(inv_s2, 0.0, -inv_s2),
                ev=(0.0, 1.0, 0.0),
                ew=(inv_s2, 0.0, inv_s2),
                outer_u=(-0.098, 0.098),
                outer_v=(-h_half, h_half),
                hole_u=(-0.018, 0.018),
                hole_v=(-0.050, 0.050),
                outer_layers=diag_outer_layers,
                hole_layers=diag_hole_layers,
                floor_color=COL_CAVITY,
                outer_corner_chamfer=0.010,
            )

    # --------------------------------------------------------------------------
    # 2. TOP & BOTTOM HORIZONTAL PERIMETER RAILS
    # --------------------------------------------------------------------------
    rail_planes = [
        (0.0, -1.0, -0.805, 0.4),   # Inner face toward crate center
        (1.0, 0.0, 0.796, 1.0),     # Right seam against corner cap
        (0.0, 1.0, 0.996, 1.0),     # Outer face of crate
        (-1.0, 0.0, 0.796, 1.0),    # Left seam against corner cap
    ]
    for rot in range(4):
        for flip_y in (False, True):
            mb.set_symmetry(rot, flip_y)
            mb.loft_halfplanes(
                origin=(0.0, 0.0, 0.0),
                eu=(1.0, 0.0, 0.0),
                ev=(0.0, 0.0, 1.0),
                ew=(0.0, 1.0, 0.0),
                planes=rail_planes,
                layers=[
                    (0.805, 0.014, COL_SEAM_DARK),
                    (0.818, 0.003, COL_FRAME_EDGE),
                    (0.824, 0.0, COL_FRAME_MAIN),
                    (0.960, 0.0, COL_FRAME_MAIN),
                    (0.972, 0.008, COL_FRAME_EDGE),
                    (0.995, 0.034, COL_FRAME_EDGE),
                    (1.001, 0.044, COL_FRAME_MAIN),
                ],
                cap_top=True,
                cap_bottom=True,
            )

    # --------------------------------------------------------------------------
    # 3. FOUR SIDE FACES: EXACT MITERED PICTURE FRAME + X-BRACE / 3 HORIZONTAL SLATS
    # --------------------------------------------------------------------------
    U_OUT, V_OUT = 0.784, 0.784
    FRAME_W = 0.122
    U_IN, V_IN = U_OUT - FRAME_W, V_OUT - FRAME_W  # 0.662, 0.662

    for rot in range(4):
        mb.set_symmetry(rot, False)
        eu_side = (1.0, 0.0, 0.0)
        ev_side = (0.0, 1.0, 0.0)
        ew_side = (0.0, 0.0, 1.0)

        # Dark outer reveal groove backing plate (from column/rail seam inward)
        groove_back_planes = rect_planes(-0.815, 0.815, -0.815, 0.815)
        mb.loft_halfplanes(
            origin=(0.0, 0.0, 0.0),
            eu=eu_side,
            ev=ev_side,
            ew=ew_side,
            planes=groove_back_planes,
            layers=[(0.900, 0.0, COL_CAVITY), (0.935, 0.0, COL_CAVITY)],
            cap_top=True,
        )

        # Exact 4-bar Mitered Picture Frame (almost flush with outer column so reveal groove is 100% visible!)
        build_mitered_picture_frame(
            mb,
            u_out=U_OUT,
            v_out=V_OUT,
            u_in=U_IN,
            v_in=V_IN,
            layers=[
                # (w_depth, out_inset, in_inset, miter_gap, color)
                (0.935, 0.000, -0.022, 0.002, COL_CAVITY),
                (0.948, 0.004, -0.012, 0.004, COL_SEAM_DARK),
                (0.980, 0.014, 0.012, 0.009, COL_FRAME_EDGE),
                (0.986, 0.018, 0.018, 0.012, COL_FRAME_MAIN),
            ],
        )

        if rot in (0, 2):
            # ------------------------------------------------------------------
            # FACE TYPE A (+Z and -Z): RECESSED SLATE PANEL + UNIFIED "X" BRACE
            # ------------------------------------------------------------------
            panel_planes = rect_planes(-U_IN + 0.004, U_IN - 0.004, -V_IN + 0.004, V_IN - 0.004)
            mb.loft_halfplanes(
                origin=(0.0, 0.0, 0.0),
                eu=eu_side,
                ev=ev_side,
                ew=ew_side,
                planes=panel_planes,
                layers=[
                    (0.935, 0.0, COL_CAVITY),
                    (0.942, 0.012, COL_SEAM_DARK),
                    (0.946, 0.022, COL_PANEL_DARK),
                ],
                cap_top=True,
            )

            build_unified_x_brace(
                mb,
                u_lim=U_IN + 0.004,
                v_lim=V_IN + 0.004,
                layers=[
                    (0.944, 0.088, COL_CAVITY),
                    (0.952, 0.076, COL_SEAM_DARK),
                    (0.976, 0.050, COL_CLAMP_EDGE),
                    (0.982, 0.036, COL_FRAME_MAIN),
                ],
            )
        else:
            # ------------------------------------------------------------------
            # FACE TYPE B (+X and -X): 3 HORIZONTAL ARMOR PLANKS WITH GROOVES
            # ------------------------------------------------------------------
            plank_u = U_IN - 0.008
            plank_ranges = [
                (-V_IN + 0.008, -0.232),
                (-0.204, 0.204),
                (0.232, V_IN - 0.008),
            ]
            plank_layers = [
                (0.935, 0.0, COL_CAVITY),
                (0.944, 0.008, COL_SEAM_DARK),
                (0.960, 0.020, COL_PANEL_EDGE),
                (0.965, 0.028, COL_PANEL_MAIN),
            ]
            for pv0, pv1 in plank_ranges:
                p_planes = rect_planes(-plank_u, plank_u, pv0, pv1)
                mb.loft_halfplanes(
                    origin=(0.0, 0.0, 0.0),
                    eu=eu_side,
                    ev=ev_side,
                    ew=ew_side,
                    planes=p_planes,
                    layers=plank_layers,
                    cap_top=True,
                )

    # --------------------------------------------------------------------------
    # 4. TOP FACE (+Y): FLAT DECK WITH 4 RECESSED HANDLE SLOTS + CENTRAL HATCH
    # --------------------------------------------------------------------------
    mb.set_symmetry(0, False)
    eu_top = (1.0, 0.0, 0.0)
    ev_top = (0.0, 0.0, -1.0)
    ew_top = (0.0, 1.0, 0.0)

    slot_outer_layers = [
        (0.930, 0.005, COL_SEAM_DARK),
        (0.954, 0.0, COL_FRAME_MAIN),
        (0.960, 0.004, COL_FRAME_EDGE),
        (0.963, 0.008, COL_FRAME_MAIN),
    ]
    slot_hole_layers = [
        (0.963, 0.0, COL_FRAME_EDGE),
        (0.940, -0.022, COL_FRAME_BASE),
        (0.830, -0.026, COL_CAVITY),
    ]

    for v_sign in (-1.0, 1.0):
        v_min = 0.465 if v_sign > 0 else -0.802
        v_max = 0.802 if v_sign > 0 else -0.465
        hv_min = 0.555 if v_sign > 0 else -0.715
        hv_max = 0.715 if v_sign > 0 else -0.555

        # Left handle slot unit
        mb.build_holed_plate(
            origin=(0.0, 0.0, 0.0),
            eu=eu_top,
            ev=ev_top,
            ew=ew_top,
            outer_u=(-0.802, -0.105),
            outer_v=(v_min, v_max),
            hole_u=(-0.610, -0.205),
            hole_v=(hv_min, hv_max),
            outer_layers=slot_outer_layers,
            hole_layers=slot_hole_layers,
            floor_color=COL_CAVITY,
            outer_corner_chamfer=0.006,
        )
        # Right handle slot unit
        mb.build_holed_plate(
            origin=(0.0, 0.0, 0.0),
            eu=eu_top,
            ev=ev_top,
            ew=ew_top,
            outer_u=(0.105, 0.802),
            outer_v=(v_min, v_max),
            hole_u=(0.205, 0.610),
            hole_v=(hv_min, hv_max),
            outer_layers=slot_outer_layers,
            hole_layers=slot_hole_layers,
            floor_color=COL_CAVITY,
            outer_corner_chamfer=0.006,
        )
        # Center bridge between the two handle slots
        bridge_planes = rect_chamfered_planes(-0.102, 0.102, v_min, v_max, 0.006)
        mb.loft_halfplanes(
            origin=(0.0, 0.0, 0.0),
            eu=eu_top,
            ev=ev_top,
            ew=ew_top,
            planes=bridge_planes,
            layers=slot_outer_layers,
            cap_top=True,
        )

    # Central Deck Band (v in [-0.460, +0.460])
    deck_ranges = [
        (-0.802, -0.462),
        (-0.458, 0.458),
        (0.462, 0.802),
    ]
    for du0, du1 in deck_ranges:
        d_planes = rect_chamfered_planes(du0, du1, -0.460, 0.460, 0.006)
        mb.loft_halfplanes(
            origin=(0.0, 0.0, 0.0),
            eu=eu_top,
            ev=ev_top,
            ew=ew_top,
            planes=d_planes,
            layers=slot_outer_layers,
            cap_top=True,
        )

    # Central Raised Rimmed Inspection Hatch Plate on Top
    mb.build_holed_plate(
        origin=(0.0, 0.0, 0.0),
        eu=eu_top,
        ev=ev_top,
        ew=ew_top,
        outer_u=(-0.410, 0.410),
        outer_v=(-0.390, 0.390),
        hole_u=(-0.368, 0.368),
        hole_v=(-0.348, 0.348),
        outer_layers=[
            (0.960, 0.0, COL_SEAM_DARK),
            (0.965, 0.003, COL_FRAME_BASE),
            (0.975, 0.009, COL_CLAMP_EDGE),
            (0.979, 0.014, COL_FRAME_MAIN),
        ],
        hole_layers=[
            (0.979, 0.0, COL_CLAMP_EDGE),
            (0.969, -0.008, COL_SEAM_DARK),
            (0.967, -0.012, COL_PANEL_MAIN),
        ],
        floor_color=COL_PANEL_MAIN,
        outer_corner_chamfer=0.020,
    )

    # --------------------------------------------------------------------------
    # 5. BOTTOM FACE (-Y): REINFORCED INDUSTRIAL SKID BASE
    # --------------------------------------------------------------------------
    mb.set_symmetry(0, True)
    for du0, du1 in [(-0.802, -0.26), (-0.25, 0.25), (0.26, 0.802)]:
        b_planes = rect_chamfered_planes(du0, du1, -0.802, 0.802, 0.010)
        mb.loft_halfplanes(
            origin=(0.0, 0.0, 0.0),
            eu=eu_top,
            ev=ev_top,
            ew=ew_top,
            planes=b_planes,
            layers=slot_outer_layers,
            cap_top=True,
        )

    return mb


def build_mitered_picture_frame(
    mb: MeshBuilder,
    u_out: float,
    v_out: float,
    u_in: float,
    v_in: float,
    layers: List[Tuple[float, float, float, float, Color4]],
) -> None:
    """
    Builds the 4 trapezoidal bars of the Mitered Picture Frame on a side face (+Z)
    with constant-width 45-degree corner miter seams and zero corner pulling.
    Each layer is (w_depth, out_inset, in_inset, miter_gap, color).
    """
    ez = (0.0, 0.0, 1.0)

    # Build each of the 4 bars (Bottom, Top, Right, Left) as a 4-vertex ring per layer
    bar_defs = ["bottom", "top", "right", "left"]

    for bar in bar_defs:
        rings: List[List[Vec3]] = []
        for w, d_out, d_in, m_gap, _ in layers:
            uo = u_out - d_out
            vo = v_out - d_out
            ui = u_in + d_in
            vi = v_in + d_in

            if bar == "bottom":
                pts = [
                    (-uo + m_gap, -vo, w),
                    (uo - m_gap, -vo, w),
                    (ui - m_gap, -vi, w),
                    (-ui + m_gap, -vi, w),
                ]
            elif bar == "top":
                pts = [
                    (-ui + m_gap, vi, w),
                    (ui - m_gap, vi, w),
                    (uo - m_gap, vo, w),
                    (-uo + m_gap, vo, w),
                ]
            elif bar == "right":
                pts = [
                    (ui, -vi + m_gap, w),
                    (uo, -vo + m_gap, w),
                    (uo, vo - m_gap, w),
                    (ui, vi - m_gap, w),
                ]
            else:  # left
                pts = [
                    (-uo, -vo + m_gap, w),
                    (-ui, -vi + m_gap, w),
                    (-ui, vi - m_gap, w),
                    (-uo, vo - m_gap, w),
                ]
            rings.append(pts)

        for k in range(len(layers) - 1):
            r0 = rings[k]
            r1 = rings[k + 1]
            c0 = layers[k][4]
            c1 = layers[k + 1][4]
            for i in range(4):
                j = (i + 1) % 4
                dx = r0[j][0] - r0[i][0]
                dy = r0[j][1] - r0[i][1]
                hint = v3_norm((dy, -dx, 0.4))
                mb.add_quad(r0[i], r0[j], r1[j], r1[i], c0, c0, c1, c1, hint)

        top_r = rings[-1]
        w_top, d_out_top, d_in_top, m_gap_top, tcol = layers[-1]
        rim = 0.014
        uo_c = u_out - d_out_top - rim
        vo_c = v_out - d_out_top - rim
        ui_c = u_in + d_in_top + rim
        vi_c = v_in + d_in_top + rim
        mg_c = m_gap_top + rim * 0.4
        if bar == "bottom":
            core_r = [(-uo_c + mg_c, -vo_c, w_top), (uo_c - mg_c, -vo_c, w_top), (ui_c - mg_c, -vi_c, w_top), (-ui_c + mg_c, -vi_c, w_top)]
        elif bar == "top":
            core_r = [(-ui_c + mg_c, vi_c, w_top), (ui_c - mg_c, vi_c, w_top), (uo_c - mg_c, vo_c, w_top), (-uo_c + mg_c, vo_c, w_top)]
        elif bar == "right":
            core_r = [(ui_c, -vi_c + mg_c, w_top), (uo_c, -vo_c + mg_c, w_top), (uo_c, vo_c - mg_c, w_top), (ui_c, vi_c - mg_c, w_top)]
        else:
            core_r = [(-uo_c, -vo_c + mg_c, w_top), (-ui_c, -vi_c + mg_c, w_top), (-ui_c, vi_c - mg_c, w_top), (-uo_c, vo_c - mg_c, w_top)]

        ecol = COL_CLAMP_EDGE
        for i in range(4):
            j = (i + 1) % 4
            mb.add_quad(top_r[i], top_r[j], core_r[j], core_r[i], ecol, ecol, tcol, tcol, ez)
        mb.add_quad(core_r[0], core_r[1], core_r[2], core_r[3], tcol, tcol, tcol, tcol, ez)


def build_unified_x_brace(
    mb: MeshBuilder,
    u_lim: float,
    v_lim: float,
    layers: List[Tuple[float, float, Color4]],
) -> None:
    diag_len = math.sqrt(u_lim * u_lim + v_lim * v_lim)
    rings: List[List[Vec3]] = []

    for w_depth, bar_half_w, _ in layers:
        du = bar_half_w * diag_len / v_lim
        dv = bar_half_w * diag_len / u_lim

        pts_2d: List[Vec2] = [
            (du, 0.0),
            (u_lim, v_lim - dv),
            (u_lim, v_lim),
            (u_lim - du, v_lim),
            (0.0, dv),
            (-u_lim + du, v_lim),
            (-u_lim, v_lim),
            (-u_lim, v_lim - dv),
            (-du, 0.0),
            (-u_lim, -v_lim + dv),
            (-u_lim, -v_lim),
            (-u_lim + du, -v_lim),
            (0.0, -dv),
            (u_lim - du, -v_lim),
            (u_lim, -v_lim),
            (u_lim, -v_lim + dv),
        ]
        rings.append([(u, v, w_depth) for (u, v) in pts_2d])

    num_v = 16
    for k in range(len(layers) - 1):
        r0 = rings[k]
        r1 = rings[k + 1]
        c0 = layers[k][2]
        c1 = layers[k + 1][2]
        for i in range(num_v):
            j = (i + 1) % num_v
            dx = r0[j][0] - r0[i][0]
            dy = r0[j][1] - r0[i][1]
            hint = v3_norm((dy, -dx, 0.35))
            mb.add_quad(r0[i], r0[j], r1[j], r1[i], c0, c0, c1, c1, hint)

    top = rings[-1]
    tcol = layers[-1][2]
    ez = (0.0, 0.0, 1.0)

    mb.add_quad(top[0], top[4], top[8], top[12], tcol, tcol, tcol, tcol, ez)
    mb.add_quad(top[0], top[1], top[3], top[4], tcol, tcol, tcol, tcol, ez)
    mb.add_tri(top[1], top[2], top[3], tcol, tcol, tcol, ez)
    mb.add_quad(top[4], top[5], top[7], top[8], tcol, tcol, tcol, tcol, ez)
    mb.add_tri(top[5], top[6], top[7], tcol, tcol, tcol, ez)
    mb.add_quad(top[8], top[9], top[11], top[12], tcol, tcol, tcol, tcol, ez)
    mb.add_tri(top[9], top[10], top[11], tcol, tcol, tcol, ez)
    mb.add_quad(top[12], top[13], top[15], top[0], tcol, tcol, tcol, tcol, ez)
    mb.add_tri(top[13], top[14], top[15], tcol, tcol, tcol, ez)


# ==============================================================================
# PROCEDURAL TEXTURE GENERATOR (Pure Python PNG via zlib — Distressed Gunmetal)
# ==============================================================================
def make_png_bytes(width: int, height: int, rgb_rows: List[bytes]) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    raw = b"".join(b"\x00" + row for row in rgb_rows)
    idat = zlib.compress(raw, level=6)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


def generate_gunmetal_texture(size: int = 256) -> bytes:
    rng = random.Random(42)
    grid = [[244 for _ in range(size)] for _ in range(size)]

    for _ in range(320):
        cx = rng.randrange(size)
        cy = rng.randrange(size)
        r = rng.randint(5, 22)
        delta = rng.randint(-9, 8)
        for dy in range(-r, r + 1):
            y = (cy + dy) % size
            for dx in range(-r, r + 1):
                if dx * dx + dy * dy <= r * r:
                    x = (cx + dx) % size
                    grid[y][x] = max(218, min(255, grid[y][x] + delta // 3))

    for _ in range(140):
        x0 = rng.randrange(size)
        y0 = rng.randrange(size)
        length = rng.randint(4, 16)
        angle = rng.uniform(0.0, math.tau)
        ca, sa = math.cos(angle), math.sin(angle)
        bright = rng.choice([252, 254, 226, 230])
        for step in range(length):
            x = int(x0 + ca * step) % size
            y = int(y0 + sa * step) % size
            grid[y][x] = bright

    rows: List[bytes] = []
    for y in range(size):
        row = bytearray(size * 3)
        for x in range(size):
            v = grid[y][x]
            idx = x * 3
            row[idx] = v
            row[idx + 1] = v
            row[idx + 2] = min(255, v + 2)
        rows.append(bytes(row))

    return make_png_bytes(size, size, rows)


# ==============================================================================
# GLB (Binary glTF 2.0) EXPORTER
# ==============================================================================
def export_glb(mb: MeshBuilder, out_path: str) -> None:
    num_verts = len(mb.positions)
    num_indices = len(mb.indices)

    pos_bin = bytearray()
    norm_bin = bytearray()
    uv_bin = bytearray()
    col_bin = bytearray()

    min_p = [1e9, 1e9, 1e9]
    max_p = [-1e9, -1e9, -1e9]

    for i in range(num_verts):
        px, py, pz = mb.positions[i]
        nx, ny, nz = mb.normals[i]
        u, v = mb.uvs[i]
        r, g, b, a = mb.colors[i]

        for axis, val in enumerate((px, py, pz)):
            if val < min_p[axis]:
                min_p[axis] = val
            if val > max_p[axis]:
                max_p[axis] = val

        pos_bin.extend(struct.pack("<3f", px, py, pz))
        norm_bin.extend(struct.pack("<3f", nx, ny, nz))
        uv_bin.extend(struct.pack("<2f", u, v))
        col_bin.extend(struct.pack("<4f", r, g, b, a))

    idx_bin = bytearray()
    for idx in mb.indices:
        idx_bin.extend(struct.pack("<I", idx))

    png_bytes = generate_gunmetal_texture(256)

    def pad4(b: bytearray) -> None:
        while len(b) % 4 != 0:
            b.append(0)

    buffer_data = bytearray()
    views = []

    def add_view(data: bytes, target: Optional[int] = None) -> int:
        offset = len(buffer_data)
        buffer_data.extend(data)
        pad4(buffer_data)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target is not None:
            view["target"] = target
        views.append(view)
        return len(views) - 1

    v_pos = add_view(pos_bin, 34962)
    v_norm = add_view(norm_bin, 34962)
    v_uv = add_view(uv_bin, 34962)
    v_col = add_view(col_bin, 34962)
    v_idx = add_view(idx_bin, 34963)
    v_img = add_view(png_bytes, None)

    gltf = {
        "asset": {"version": "2.0", "generator": "TANKUS Procedural Crate Builder"},
        "scene": 0,
        "scenes": [{"name": "IndustrialCrateScene", "nodes": [0]}],
        "nodes": [{"name": "IndustrialCrate", "mesh": 0}],
        "meshes": [
            {
                "name": "IndustrialCrateMesh",
                "primitives": [
                    {
                        "attributes": {
                            "POSITION": 0,
                            "NORMAL": 1,
                            "TEXCOORD_0": 2,
                            "COLOR_0": 3,
                        },
                        "indices": 4,
                        "material": 0,
                    }
                ],
            }
        ],
        "materials": [
            {
                "name": "IndustrialGunmetal",
                "pbrMetallicRoughness": {
                    "baseColorTexture": {"index": 0},
                    "baseColorFactor": [1.0, 1.0, 1.0, 1.0],
                    "metallicFactor": 0.32,
                    "roughnessFactor": 0.52,
                },
            }
        ],
        "textures": [{"sampler": 0, "source": 0}],
        "samplers": [
            {
                "magFilter": 9729,
                "minFilter": 9987,
                "wrapS": 10497,
                "wrapT": 10497,
            }
        ],
        "images": [{"bufferView": v_img, "mimeType": "image/png", "name": "GunmetalDetail"}],
        "accessors": [
            {
                "bufferView": v_pos,
                "componentType": 5126,
                "count": num_verts,
                "type": "VEC3",
                "min": min_p,
                "max": max_p,
            },
            {
                "bufferView": v_norm,
                "componentType": 5126,
                "count": num_verts,
                "type": "VEC3",
            },
            {
                "bufferView": v_uv,
                "componentType": 5126,
                "count": num_verts,
                "type": "VEC2",
            },
            {
                "bufferView": v_col,
                "componentType": 5126,
                "count": num_verts,
                "type": "VEC4",
            },
            {
                "bufferView": v_idx,
                "componentType": 5125,
                "count": num_indices,
                "type": "SCALAR",
            },
        ],
        "bufferViews": views,
        "buffers": [{"byteLength": len(buffer_data)}],
    }

    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4 != 0:
        json_bytes += b" "

    total_len = 12 + 8 + len(json_bytes) + 8 + len(buffer_data)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total_len))
        f.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        f.write(json_bytes)
        f.write(struct.pack("<II", len(buffer_data), 0x004E4942))
        f.write(buffer_data)

    print(
        f"Exported {out_path}: {num_verts} vertices, {num_indices // 3} triangles, {total_len / 1024:.1f} KB"
    )


if __name__ == "__main__":
    mesh = build_crate_mesh()
    out_file = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "assets",
        "props",
        "industrial_crate",
        "industrial_crate.glb",
    )
    export_glb(mesh, out_file)
