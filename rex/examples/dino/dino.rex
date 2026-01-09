// Respect to the guys who made this game

use rex::ui
use rex::time
use rex::random
use rex::collections as col
struct Obstacle { x: f64, y: f64, w: f64, h: f64, kind: i32, gap: f64, size: i32 }
struct Cloud { x: f64, y: f64, gap: f64 }
struct Star { x: f64, y: f64, src_y: f64 }

fn clamp(v: f64, lo: f64, hi: f64) -> f64 {
    if v < lo {
        return lo
    }
    if v > hi {
        return hi
    }
    return v
}

fn rects_overlap(ax: f64, ay: f64, aw: f64, ah: f64, bx: f64, by: f64, bw: f64, bh: f64) -> bool {
    return ax < (bx + bw) && (ax + aw) > bx && ay < (by + bh) && (ay + ah) > by
}

fn main() {
    random.seed(time.now_ms())
// Game constants
    let title = "Rex Dino"
    let bg = "#F7F7F7"
    let fg = "#202124"
    let msg_start = "Space to start"
    let msg_restart = "Space or click to restart"
    let msg_over = "Game Over"


    let win_w: i32 = 600
    let win_h: i32 = 150

// Game assets 
    let sheet = ui.image_load("examples/dino/ic/200-offline-sprite.png")
    let sound_jump = "examples/dino/sound/jump_sound.wav"
    let sound_score = "examples/dino/sound/100points.mp3"
    let sound_hit = "examples/dino/sound/lose.mp3"
// Sprite sheet coordinates and sizes
    let sheet_scale: f64 = 2


    let trex_x: f64 = 1678
    let trex_y: f64 = 2
    let cactus_small_x: f64 = 446
    let cactus_small_y: f64 = 2
    let cactus_large_x: f64 = 652
    let cactus_large_y: f64 = 2
    let ptero_x: f64 = 260
    let ptero_y: f64 = 2
    let restart_x: f64 = 2
    let restart_y: f64 = 2
    let horizon_x: f64 = 2
    let horizon_y_src: f64 = 104
    let cloud_x: f64 = 166
    let cloud_y: f64 = 2
    let moon_x: f64 = 954
    let moon_y: f64 = 2
    let star_x: f64 = 1276
    let star_y: f64 = 2


    let trex_w: f64 = 44
    let trex_h: f64 = 47
    let trex_duck_w: f64 = 59
    let trex_duck_h: f64 = trex_h
    let trex_src_w: f64 = trex_w * sheet_scale
    let trex_src_h: f64 = trex_h * sheet_scale
    let trex_duck_src_w: f64 = trex_duck_w * sheet_scale

    let cactus_small_w: f64 = 17
    let cactus_small_h: f64 = 35
    let cactus_small_src_w: f64 = cactus_small_w * sheet_scale
    let cactus_small_src_h: f64 = cactus_small_h * sheet_scale

    let cactus_large_w: f64 = 25
    let cactus_large_h: f64 = 50
    let cactus_large_src_w: f64 = cactus_large_w * sheet_scale
    let cactus_large_src_h: f64 = cactus_large_h * sheet_scale

    let ptero_w: f64 = 46
    let ptero_h: f64 = 40
    let ptero_src_w: f64 = ptero_w * sheet_scale
    let ptero_src_h: f64 = ptero_h * sheet_scale

    let restart_w: f64 = 36
    let restart_h: f64 = 32
    let restart_src_w: f64 = restart_w * sheet_scale
    let restart_src_h: f64 = restart_h * sheet_scale

    let horizon_w: f64 = 600
    let horizon_h: f64 = 12
    let horizon_src_w: f64 = horizon_w * sheet_scale
    let horizon_src_h: f64 = horizon_h * sheet_scale
    let horizon_y: f64 = 127

    let cloud_w: f64 = 46
    let cloud_h: f64 = 14
    let cloud_src_w: f64 = cloud_w * sheet_scale
    let cloud_src_h: f64 = cloud_h * sheet_scale

    let moon_w: f64 = 20
    let moon_h: f64 = 40
    let moon_src_w: f64 = moon_w * sheet_scale
    let moon_src_h: f64 = moon_h * sheet_scale

    let star_size: f64 = 9
    let star_src_size: f64 = star_size * sheet_scale

    let tick_ms: f64 = 16
    let dino_x: f64 = 50
    let gravity: f64 = 0.6
    let jump_vy: f64 = 11

    let base_speed: f64 = 6
    let max_speed: f64 = 13
    let speed_accel: f64 = 0.001

    let gap_coeff: f64 = 0.6
    let max_gap_coeff: f64 = 1.5

    let score_step_px: f64 = 40


    let cloud_speed: f64 = 0.2
    let cloud_frequency: f64 = 0.5
    let cloud_max: f64 = 6
    let cloud_gap_min: f64 = 100
    let cloud_gap_max: f64 = 400
    let cloud_sky_min: f64 = 71
    let cloud_sky_max: f64 = 30

    let night_interval: i32 = 500
    let moon_speed: f64 = 0.25
    let star_speed: f64 = 0.3
    let star_count: f64 = 2
    let star_max_y: f64 = 70

    let bottom_pad: f64 = 10
    let ground_y: f64 = win_h - bottom_pad
    let track_y: f64 = horizon_y
    let track_w: f64 = horizon_w

    mut state: i32 = 0
    mut score: i32 = 0
    mut best: i32 = 0
    mut speed: f64 = base_speed
    mut score_dist: f64 = 0

    mut dino_y: f64 = 0
    mut dino_vy: f64 = 0

    mut track_x: f64 = 0

    mut run_timer: f64 = 0
    mut run_frame: i32 = 0
    mut bird_timer: f64 = 0
    mut bird_frame: i32 = 0

    mut obstacles = col.vec_new<Obstacle>()
    mut clouds = col.vec_new<Cloud>()
    mut stars = col.vec_new<Star>()
    mut night_active: bool = false
    mut last_night_score: i32 = 0
    mut titlebar_dark: bool = false
    let moon_phases = [140, 120, 100, 60, 40, 20, 0]
    mut moon_phase: i32 = 0
    mut moon_x_pos: f64 = win_w - 50
    let moon_y_pos: f64 = 30

    col.vec_push(&mut clouds, Cloud.new(win_w, random.int(cloud_sky_max, cloud_sky_min), random.int(cloud_gap_min, cloud_gap_max)))

    mut last = time.now_ms()
    mut acc: f64 = 0
    mut jump_request: bool = false

    while ui.begin(&title, win_w, win_h) {
        ui.redraw()

        let now = time.now_ms()
        mut dt = now - last
        if dt < 0 {
            dt = 0
        }
        if dt > 80 {
            dt = 80
        }
        last = now
        acc = acc + dt

        if ui.key_space() {
            jump_request = true
        }
        let duck_held = ui.key_down()

        while acc >= tick_ms {
            acc = acc - tick_ms

            if state == 0 {
                if jump_request {
                    state = 1
                    score = 0
                    score_dist = 0
                    dino_y = 0
                    dino_vy = 0
                    speed = base_speed
                    track_x = 0
                    run_timer = 0
                    run_frame = 0
                    bird_timer = 0
                    bird_frame = 0
                    col.vec_clear(&mut obstacles)
                    col.vec_clear(&mut clouds)
                    col.vec_clear(&mut stars)
                    night_active = false
                    last_night_score = 0
                    moon_phase = 0
                    moon_x_pos = win_w - 50
                    col.vec_push(&mut clouds, Cloud.new(win_w, random.int(cloud_sky_max, cloud_sky_min), random.int(cloud_gap_min, cloud_gap_max)))
                    jump_request = false
                }
            } else {
                if state == 2 {
                    if jump_request {
                        state = 1
                        score = 0
                        score_dist = 0
                        dino_y = 0
                        dino_vy = 0
                        speed = base_speed
                        track_x = 0
                        run_timer = 0
                        run_frame = 0
                        bird_timer = 0
                        bird_frame = 0
                        col.vec_clear(&mut obstacles)
                        col.vec_clear(&mut clouds)
                        col.vec_clear(&mut stars)
                        night_active = false
                        last_night_score = 0
                        moon_phase = 0
                        moon_x_pos = win_w - 50
                        col.vec_push(&mut clouds, Cloud.new(win_w, random.int(cloud_sky_max, cloud_sky_min), random.int(cloud_gap_min, cloud_gap_max)))
                        jump_request = false
                    }
                }

                if state == 1 {

                    score_dist = score_dist + speed
                    while score_dist >= score_step_px {
                        score_dist = score_dist - score_step_px
                        score = score + 1
                        if (score % 100) == 0 {
                            ui.play_sound(&sound_score)
                        }
                    }


                    if speed < max_speed {
                        speed = speed + speed_accel
                        if speed > max_speed {
                            speed = max_speed
                        }
                    }


                    if score > 0 && (score % night_interval) == 0 && score != last_night_score {
                        last_night_score = score
                        night_active = !night_active
                        if night_active {
                            moon_phase = moon_phase + 1
                            if moon_phase >= 7 {
                                moon_phase = 0
                            }
                            moon_x_pos = win_w - 50
                            col.vec_clear(&mut stars)
                            let seg = win_w / star_count
                            mut si: f64 = 0
                            while si < star_count {
                                let x0 = seg * si
                                let x1 = seg * (si + 1)
                                let sx = random.int(x0, x1)
                                let sy = random.int(0, star_max_y)
                                let ssy = star_y + star_src_size * si
                                col.vec_push(&mut stars, Star.new(sx, sy, ssy))
                                si = si + 1
                            }
                        } else {
                            col.vec_clear(&mut stars)
                        }
                    }

                    if night_active {
                        moon_x_pos = moon_x_pos - moon_speed
                        if moon_x_pos < -moon_w {
                            moon_x_pos = win_w
                        }
                        mut next_stars = col.vec_new<Star>()
                        let sn = col.vec_len(&stars)
                        mut si: f64 = 0
                        while si < sn {
                            let s = col.vec_get(&stars, si)
                            mut nx = s.x - star_speed
                            if nx < -star_size {
                                nx = win_w
                            }
                            col.vec_push(&mut next_stars, Star.new(nx, s.y, s.src_y))
                            si = si + 1
                        }
                        stars = next_stars
                    }

                    run_timer = run_timer + tick_ms
                    if run_timer >= 80 {
                        run_timer = 0
                        run_frame = 1 - run_frame
                    }
                    bird_timer = bird_timer + tick_ms
                    if bird_timer >= 170 {
                        bird_timer = 0
                        bird_frame = 1 - bird_frame
                    }

                    if jump_request && dino_y <= 0 {
                        dino_vy = jump_vy
                        ui.play_sound(&sound_jump)
                        jump_request = false
                    }

                    if duck_held && dino_y > 0 {
                        dino_vy = dino_vy - gravity * 1.2
                    }

                    dino_vy = dino_vy - gravity
                    dino_y = dino_y + dino_vy
                    if dino_y < 0 {
                        dino_y = 0
                        dino_vy = 0
                    }

                    track_x = track_x - speed
                    if track_x <= -track_w {
                        track_x = track_x + track_w
                    }


                    let cloud_dx = (cloud_speed * speed * tick_ms) / 1000
                    mut cloud_step: f64 = cloud_dx
                    if cloud_step < 1 {
                        cloud_step = 1
                    }
                    mut next_clouds = col.vec_new<Cloud>()
                    let cn = col.vec_len(&clouds)
                    mut ci: f64 = 0
                    while ci < cn {
                        let c = col.vec_get(&clouds, ci)
                        let nx = c.x - cloud_step
                        if (nx + cloud_w) > 0 {
                            col.vec_push(&mut next_clouds, Cloud.new(nx, c.y, c.gap))
                        }
                        ci = ci + 1
                    }
                    clouds = next_clouds
                    let cn2 = col.vec_len(&clouds)
                    if cn2 <= 0 {
                        col.vec_push(&mut clouds, Cloud.new(win_w, random.int(cloud_sky_max, cloud_sky_min), random.int(cloud_gap_min, cloud_gap_max)))
                    } else if cn2 < cloud_max {
                        let last_c = col.vec_get(&clouds, cn2 - 1)
                        if (win_w - last_c.x) > last_c.gap && random.float() < cloud_frequency {
                            col.vec_push(&mut clouds, Cloud.new(win_w, random.int(cloud_sky_max, cloud_sky_min), random.int(cloud_gap_min, cloud_gap_max)))
                        }
                    }


                    let on = col.vec_len(&obstacles)
                    mut should_spawn: bool = false
                    if on <= 0 {
                        should_spawn = true
                    } else {
                        let last_o = col.vec_get(&obstacles, on - 1)
                        if (last_o.x + last_o.w + last_o.gap) < win_w {
                            should_spawn = true
                        }
                    }

                    if should_spawn {

                        mut kind: i32 = 0
                        if speed >= 8.5 && random.int(0, 9) >= 7 {
                            kind = 2
                        } else {
                            kind = random.int(0, 1)
                        }

                        mut ow: f64 = 0
                        mut oh: f64 = 0
                        mut oy: f64 = 0
                        mut base_min_gap: f64 = 120
                        mut size: i32 = 1
                        if kind == 0 {
                            size = random.int(1, 3)
                            if speed < 4 {
                                size = 1
                            }
                            ow = cactus_small_w * size
                            oh = cactus_small_h
                            oy = ground_y - oh
                        } else if kind == 1 {
                            size = random.int(1, 3)
                            if speed < 7 {
                                size = 1
                            }
                            ow = cactus_large_w * size
                            oh = cactus_large_h
                            oy = ground_y - oh
                        } else {
                            base_min_gap = 150
                            ow = ptero_w
                            oh = ptero_h
                            let lane = random.int(0, 2)
                            if lane == 0 {
                                oy = 100
                            } else if lane == 1 {
                                oy = 75
                            } else {
                                oy = 50
                            }
                        }

                        let min_gap = ow * speed + base_min_gap * gap_coeff
                        let max_gap = min_gap * max_gap_coeff
                        let gap = random.int(min_gap, max_gap)
                        col.vec_push(&mut obstacles, Obstacle.new(win_w + 40, oy, ow, oh, kind, gap, size))
                    }

                    mut dw: f64 = trex_w
                    mut dh: f64 = trex_h
                    if dino_y > 0 {
                        dw = trex_w
                        dh = trex_h
                    } else if duck_held {
                        dw = trex_duck_w
                        dh = trex_duck_h
                    }
                    let dx = dino_x
                    let dy = ground_y - dh - dino_y


                    mut d_l: f64 = 7
                    mut d_r: f64 = 7
                    mut d_t: f64 = 5
                    mut d_b: f64 = 5
                    if duck_held && dino_y <= 0 {
                        d_l = 4
                        d_r = 4
                        d_t = 2
                        d_b = 2
                    } else if dino_y > 0 {
                        d_l = 10
                        d_r = 10
                        d_t = 8
                        d_b = 6
                    }

                    let mut d_hit_x = dx + d_l
                    let mut d_hit_y = dy + d_t
                    let mut d_hit_w = clamp(dw - d_l - d_r, 1, dw)
                    let mut d_hit_h = clamp(dh - d_t - d_b, 1, dh)
                    if duck_held && dino_y <= 0 {
                        let duck_hit_h: f64 = 25
                        d_hit_h = clamp(duck_hit_h - d_t - d_b, 1, duck_hit_h)
                        d_hit_y = dy + (dh - duck_hit_h) + d_t
                    }

                    mut hit: bool = false
                    mut next = col.vec_new<Obstacle>()
                    mut i: f64 = 0
                    let n = col.vec_len(&obstacles)
                    while i < n {
                        let o = col.vec_get(&obstacles, i)
                        let nx = o.x - speed
                        let no = Obstacle.new(nx, o.y, o.w, o.h, o.kind, o.gap, o.size)
                        if (nx + no.w) > -50 {
                            mut o_l: f64 = 2
                            mut o_r: f64 = 2
                            mut o_t: f64 = 6
                            mut o_b: f64 = 2
                            if no.kind == 1 {
                                o_l = 3
                                o_r = 3
                                o_t = 10
                            } else if no.kind == 2 {
                                o_l = 8
                                o_r = 8
                                o_t = 6
                                o_b = 6
                            }
                            let o_hit_x = no.x + o_l
                            let o_hit_y = no.y + o_t
                            let o_hit_w = clamp(no.w - o_l - o_r, 1, no.w)
                            let o_hit_h = clamp(no.h - o_t - o_b, 1, no.h)

                            if rects_overlap(d_hit_x, d_hit_y, d_hit_w, d_hit_h, o_hit_x, o_hit_y, o_hit_w, o_hit_h) {
                                hit = true
                            }
                            col.vec_push(&mut next, no)
                        }
                        i = i + 1
                    }
                    obstacles = next

                    if hit {
                        ui.play_sound(&sound_hit)
                        state = 2
                        if score > best {
                            best = score
                        }
                    }
                }
            }
        }

        ui.invert(night_active)
        let want_titlebar_dark = night_active
        if want_titlebar_dark != titlebar_dark {
            titlebar_dark = want_titlebar_dark
            ui.titlebar_dark(titlebar_dark)
        }
        ui.clear(&bg)


        if night_active {
            mut si: f64 = 0
            let sn = col.vec_len(&stars)
            while si < sn {
                let s = col.vec_get(&stars, si)
                ui.image_region(&sheet, star_x, s.src_y, star_src_size, star_src_size, s.x, s.y, star_size, star_size)
                si = si + 1
            }

            let phase_offset = moon_phases[moon_phase]
            mut moon_sw = moon_src_w
            mut moon_dw = moon_w
            if moon_phase == 3 {
                moon_sw = moon_src_w * 2
                moon_dw = moon_w * 2
            }
            let moon_sx = moon_x + phase_offset * sheet_scale
            ui.image_region(&sheet, moon_sx, moon_y, moon_sw, moon_src_h, moon_x_pos, moon_y_pos, moon_dw, moon_h)
        }


        mut ci: f64 = 0
        let cn = col.vec_len(&clouds)
        while ci < cn {
            let c = col.vec_get(&clouds, ci)
            ui.image_region(&sheet, cloud_x, cloud_y, cloud_src_w, cloud_src_h, c.x, c.y, cloud_w, cloud_h)
            ci = ci + 1
        }

        ui.image_region(&sheet, horizon_x, horizon_y_src, horizon_src_w, horizon_src_h, track_x, track_y, horizon_w, horizon_h)
        ui.image_region(&sheet, horizon_x, horizon_y_src, horizon_src_w, horizon_src_h, track_x + track_w, track_y, horizon_w, horizon_h)


        mut j: f64 = 0
        let on = col.vec_len(&obstacles)
        while j < on {
            let o = col.vec_get(&obstacles, j)
            if o.kind == 0 {
                let size: f64 = o.size
                let sw = cactus_small_src_w * size
                let sh = cactus_small_src_h
                let sx = cactus_small_x + (cactus_small_src_w * size) * (0.5 * (size - 1))
                ui.image_region(&sheet, sx, cactus_small_y, sw, sh, o.x, o.y, cactus_small_w * size, cactus_small_h)
            } else if o.kind == 1 {
                let size: f64 = o.size
                let sw = cactus_large_src_w * size
                let sh = cactus_large_src_h
                let sx = cactus_large_x + (cactus_large_src_w * size) * (0.5 * (size - 1))
                ui.image_region(&sheet, sx, cactus_large_y, sw, sh, o.x, o.y, cactus_large_w * size, cactus_large_h)
            } else {
                let sx = ptero_x + ptero_src_w * bird_frame
                ui.image_region(&sheet, sx, ptero_y, ptero_src_w, ptero_src_h, o.x, o.y, ptero_w, ptero_h)
            }
            j = j + 1
        }


        mut sx: f64 = trex_x + (88 * sheet_scale)
        mut sw: f64 = trex_src_w
        mut dw: f64 = trex_w
        mut dh: f64 = trex_h
        if state == 0 {
            sx = trex_x + (44 * sheet_scale)
        } else if state == 2 {
            sx = trex_x + (220 * sheet_scale)
        } else if dino_y > 0 {
            sx = trex_x
        } else if duck_held {
            sw = trex_duck_src_w
            dw = trex_duck_w
            if run_frame == 0 {
                sx = trex_x + (264 * sheet_scale)
            } else {
                sx = trex_x + (323 * sheet_scale)
            }
        } else {
            if run_frame == 0 {
                sx = trex_x + (88 * sheet_scale)
            } else {
                sx = trex_x + (132 * sheet_scale)
            }
        }
        ui.image_region(&sheet, sx, trex_y, sw, trex_src_h, dino_x, ground_y - dh - dino_y, dw, dh)


        ui.text(20, 16, score, &fg)
        ui.text(win_w - 120, 16, best, &fg)

        if state == 0 {
            ui.text(20, 40, &msg_start, &fg)
        }

        if state == 2 {
            let rs_x = (win_w - restart_w) / 2
            let rs_y = (win_h - restart_h) / 2 + 10
            ui.text((win_w - 80) / 2, (win_h / 2) - 20, &msg_over, &fg)
            ui.image_region(&sheet, restart_x, restart_y, restart_src_w, restart_src_h, rs_x, rs_y, restart_w, restart_h)
            if ui.mouse_pressed() {
                let mx = ui.mouse_x()
                let my = ui.mouse_y()
                if mx >= rs_x && mx <= (rs_x + restart_w) && my >= rs_y && my <= (rs_y + restart_h) {
                    jump_request = true
                }
            }
            ui.text(20, 40, &msg_restart, &fg)
        }

        ui.end()
    }
}
