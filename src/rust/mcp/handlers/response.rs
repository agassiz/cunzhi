use anyhow::Result;
use rmcp::{Error as McpError, model::Content};
use std::fs;
use std::path::PathBuf;
use base64::{Engine as _, engine::general_purpose};
use serde_json::json;

use crate::mcp::types::{McpResponse, McpResponseContent};

/// 解析 MCP 响应内容
///
/// 支持新的结构化格式和旧格式的兼容性，并生成适当的 Content 对象
pub fn parse_mcp_response(response: &str) -> Result<Vec<Content>, McpError> {
    if response.trim() == "CANCELLED" || response.trim() == "用户取消了操作" {
        return Ok(vec![Content::text("用户取消了操作".to_string())]);
    }

    // 首先尝试解析为新的结构化格式
    if let Ok(structured_response) = serde_json::from_str::<McpResponse>(response) {
        return parse_structured_response(structured_response);
    }

    // 回退到旧格式兼容性解析
    match serde_json::from_str::<Vec<McpResponseContent>>(response) {
        Ok(content_array) => {
            let mut result = Vec::new();
            let mut image_count = 0;

            // 检查是否为 Augment 客户端
            let is_augment = is_augment_client();

            // 分别收集用户文本和图片信息
            let mut user_text_parts = Vec::new();
            let mut image_info_parts = Vec::new();
            let mut collected_images = Vec::new(); // 收集图片数据用于 Augment 客户端

            for content in content_array {
                match content.content_type.as_str() {
                    "text" => {
                        if let Some(text) = content.text {
                            user_text_parts.push(text);
                        }
                    }
                    "image" => {
                        if let Some(source) = content.source {
                            if source.source_type == "base64" {
                                image_count += 1;

                                if is_augment {
                                    // Augment 客户端：收集图片信息，稍后统一处理
                                    collected_images.push((source.data.clone(), source.media_type.clone()));
                                } else {
                                    // 非 Augment 客户端：先添加图片到结果中（图片在前）
                                    result.push(Content::image(source.data.clone(), source.media_type.clone()));
                                }

                                // 根据客户端类型决定是否添加详细信息
                                if !is_augment {
                                    // 非 Augment 客户端：添加详细图片信息
                                    let base64_len = source.data.len();
                                    let preview = if base64_len > 50 {
                                        format!("{}...", &source.data[..50])
                                    } else {
                                        source.data.clone()
                                    };

                                    // 计算图片大小（base64解码后的大小）
                                    let estimated_size = (base64_len * 3) / 4; // base64编码后大约增加33%
                                    let size_str = if estimated_size < 1024 {
                                        format!("{} B", estimated_size)
                                    } else if estimated_size < 1024 * 1024 {
                                        format!("{:.1} KB", estimated_size as f64 / 1024.0)
                                    } else {
                                        format!("{:.1} MB", estimated_size as f64 / (1024.0 * 1024.0))
                                    };

                                    let image_info = format!(
                                        "=== 图片 {} ===\n类型: {}\n大小: {}\nBase64 预览: {}\n完整 Base64 长度: {} 字符",
                                        image_count, source.media_type, size_str, preview, base64_len
                                    );
                                    image_info_parts.push(image_info);
                                }
                            }
                        }
                    }
                    _ => {
                        // 未知类型，作为文本处理
                        if let Some(text) = content.text {
                            user_text_parts.push(text);
                        }
                    }
                }
            }

            // 构建文本内容
            let mut all_text_parts = Vec::new();

            // 1. 用户输入的文本
            if !user_text_parts.is_empty() {
                all_text_parts.extend(user_text_parts.clone());
            }

            // 2. 根据客户端类型处理图片
            if is_augment && !collected_images.is_empty() {
                // Augment 客户端：保存图片到临时目录并返回特殊格式
                let mut saved_images = Vec::new();

                for (index, (data, media_type)) in collected_images.iter().enumerate() {
                    match save_image_to_temp(data, media_type, index) {
                        Ok(file_path) => {
                            let image_type = media_type
                                .strip_prefix("image/")
                                .unwrap_or("png");

                            saved_images.push(json!({
                                "path": file_path,
                                "type": image_type
                            }));
                        }
                        Err(e) => {
                            eprintln!("保存图片失败: {}", e);
                            // 如果保存失败，回退到原始格式
                            result.push(Content::image(data.clone(), media_type.clone()));
                        }
                    }
                }

                // 如果成功保存了图片，构建特殊的 JSON 格式
                if !saved_images.is_empty() {
                    let user_text = user_text_parts.join("\n\n");
                    let augment_json = json!({
                        "text": user_text,
                        "images": saved_images
                    });

                    result.push(Content::text(augment_json.to_string()));

                    if result.is_empty() {
                        result.push(Content::text("用户未提供任何内容".to_string()));
                    }

                    return Ok(result);
                }
            } else if !is_augment {
                // 非 Augment 客户端：添加详细图片信息
                if !image_info_parts.is_empty() {
                    all_text_parts.extend(image_info_parts);
                }

                // 添加兼容性说明
                if image_count > 0 {
                    all_text_parts.push(format!(
                        "💡 注意：用户提供了 {} 张图片。如果 AI 助手无法显示图片，图片数据已包含在上述 Base64 信息中。",
                        image_count
                    ));
                }
            }

            // 将所有文本内容合并并添加到结果末尾（图片后面）
            if !all_text_parts.is_empty() {
                let combined_text = all_text_parts.join("\n\n");
                result.push(Content::text(combined_text));
            }

            if result.is_empty() {
                result.push(Content::text("用户未提供任何内容".to_string()));
            }

            Ok(result)
        }
        Err(_) => {
            // 如果不是JSON格式，作为纯文本处理
            Ok(vec![Content::text(response.to_string())])
        }
    }
}

/// 检查是否为 Augment 客户端
fn is_augment_client() -> bool {
    std::env::var("MCP_AI_CLIENT")
        .map(|v| v.to_lowercase() == "augment")
        .unwrap_or(false)
}

/// 获取系统临时目录
fn get_temp_dir() -> PathBuf {
    std::env::temp_dir()
}

/// 生成唯一的图片文件名
fn generate_image_filename(index: usize, extension: &str) -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let _timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis();
    let random_suffix: String = (0..6)
        .map(|_| {
            let chars = b"abcdefghijklmnopqrstuvwxyz0123456789";
            chars[fastrand::usize(..chars.len())] as char
        })
        .collect();
    format!("augment_image_{}_{}.{}", index + 1, random_suffix, extension)
}

/// 保存图片到临时目录并返回路径
fn save_image_to_temp(base64_data: &str, media_type: &str, index: usize) -> Result<String, String> {
    // 解码 Base64 数据
    let image_data = general_purpose::STANDARD
        .decode(base64_data)
        .map_err(|e| format!("Base64 解码失败: {}", e))?;

    // 根据 media_type 确定文件扩展名
    let extension = match media_type {
        "image/png" => "png",
        "image/jpeg" | "image/jpg" => "jpg",
        "image/gif" => "gif",
        "image/webp" => "webp",
        "image/bmp" => "bmp",
        _ => "png", // 默认使用 png
    };

    // 生成文件名和完整路径
    let filename = generate_image_filename(index, extension);
    let temp_dir = get_temp_dir();
    let file_path = temp_dir.join(&filename);

    // 保存文件
    fs::write(&file_path, image_data)
        .map_err(|e| format!("保存图片文件失败: {}", e))?;

    // 返回绝对路径
    file_path
        .to_str()
        .ok_or_else(|| "路径转换失败".to_string())
        .map(|s| s.to_string())
}

/// 解析新的结构化响应格式
fn parse_structured_response(response: McpResponse) -> Result<Vec<Content>, McpError> {
    let mut result = Vec::new();
    let mut text_parts = Vec::new();

    // 检查是否为 Augment 客户端
    let is_augment = is_augment_client();

    // 1. 处理选择的选项
    if !response.selected_options.is_empty() {
        text_parts.push(format!("选择的选项: {}", response.selected_options.join(", ")));
    }

    // 2. 处理用户输入文本
    if let Some(user_input) = response.user_input {
        if !user_input.trim().is_empty() {
            text_parts.push(user_input.trim().to_string());
        }
    }

    // 3. 处理图片附件
    if !response.images.is_empty() {
        if is_augment {
            // Augment 客户端：保存图片到临时目录并返回特殊格式
            let mut saved_images = Vec::new();

            for (index, image) in response.images.iter().enumerate() {
                match save_image_to_temp(&image.data, &image.media_type, index) {
                    Ok(file_path) => {
                        // 从 media_type 提取文件类型
                        let image_type = image.media_type
                            .strip_prefix("image/")
                            .unwrap_or("png");

                        saved_images.push(json!({
                            "path": file_path,
                            "type": image_type
                        }));
                    }
                    Err(e) => {
                        eprintln!("保存图片失败: {}", e);
                        // 如果保存失败，回退到原始格式
                        result.push(Content::image(image.data.clone(), image.media_type.clone()));
                    }
                }
            }

            // 如果成功保存了图片，构建特殊的 JSON 格式
            if !saved_images.is_empty() {
                let user_text = text_parts.join("\n\n");
                let augment_json = json!({
                    "text": user_text,
                    "images": saved_images
                });

                result.push(Content::text(augment_json.to_string()));
                return Ok(result);
            }
        } else {
            // 其他客户端：详细格式
            let mut image_info_parts = Vec::new();
            for (index, image) in response.images.iter().enumerate() {
                // 添加图片到结果中（图片在前）
                result.push(Content::image(image.data.clone(), image.media_type.clone()));

                // 生成图片信息
                let base64_len = image.data.len();
                let preview = if base64_len > 50 {
                    format!("{}...", &image.data[..50])
                } else {
                    image.data.clone()
                };

                // 计算图片大小
                let estimated_size = (base64_len * 3) / 4;
                let size_str = if estimated_size < 1024 {
                    format!("{} B", estimated_size)
                } else if estimated_size < 1024 * 1024 {
                    format!("{:.1} KB", estimated_size as f64 / 1024.0)
                } else {
                    format!("{:.1} MB", estimated_size as f64 / (1024.0 * 1024.0))
                };

                let filename_info = image.filename.as_ref()
                    .map(|f| format!("\n文件名: {}", f))
                    .unwrap_or_default();

                let image_info = format!(
                    "=== 图片 {} ==={}\n类型: {}\n大小: {}\nBase64 预览: {}\n完整 Base64 长度: {} 字符",
                    index + 1, filename_info, image.media_type, size_str, preview, base64_len
                );
                image_info_parts.push(image_info);
            }

            // 合并图片信息到文本部分
            text_parts.extend(image_info_parts);

            // 添加兼容性说明
            text_parts.push(format!(
                "💡 注意：用户提供了 {} 张图片。如果 AI 助手无法显示图片，图片数据已包含在上述 Base64 信息中。",
                response.images.len()
            ));
        }
    }

    // 4. 将文本内容添加到结果中
    if !text_parts.is_empty() {
        let combined_text = text_parts.join("\n\n");
        result.push(Content::text(combined_text));
    }

    // 5. 如果没有任何内容，添加默认响应
    if result.is_empty() {
        result.push(Content::text("用户未提供任何内容".to_string()));
    }

    Ok(result)
}
